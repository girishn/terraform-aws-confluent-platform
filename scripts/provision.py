#!/usr/bin/env python
"""
Provision the entire terraform-aws-confluent-platform infrastructure.

Runs in order:
  1. Terraform init + apply (VPC, EKS, CFK operator)
  2. aws eks update-kubeconfig
  3. kubectl apply -k manifests/overlays/<env>
  4. Wait for Zookeeper and Kafka StatefulSets
  5. Create Route 53 CNAME records for kafka.<domain>, b0/b1/b2.<domain>, controlcenter.<domain>

Prerequisites: terraform, aws CLI, kubectl on PATH. AWS credentials configured.

Usage:
  python scripts/provision.py [--env dev] [--auto-approve] [--skip-dns]
  cd terraform-aws-confluent-platform && python scripts/provision.py

Env overrides: TF_VAR_region, TF_VAR_name, ENV (dev|staging)
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
import time


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def run(cmd: list[str], cwd: Path | None = None, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    """Run a command; raise on failure if check=True."""
    kw = {"cwd": cwd or repo_root(), "check": check}
    if capture:
        kw["capture_output"] = True
        kw["text"] = True
    return subprocess.run(cmd, **kw)


def step(msg: str) -> None:
    print(f"\n{'='*60}\n>>> {msg}\n{'='*60}")


def get_terraform_output(name: str, env: str = "dev") -> str:
    result = run(
        ["terraform", "output", "-raw", name],
        cwd=repo_root() / "envs" / env,
        capture=True,
    )
    return result.stdout.strip()


def provision_terraform(env: str, auto_approve: bool, remove_state: bool) -> None:
    env_dir = repo_root() / "envs" / env
    if not env_dir.is_dir():
        raise SystemExit(f"Environment directory not found: {env_dir}")

    if remove_state:
        confirm = input(f"⚠️ Remove ALL Terraform state for env='{env}'? Type env name to confirm: ")
        if confirm.strip() != env:
            raise SystemExit("Aborted. State not removed.")

    if remove_state and (env_dir / "terraform.tfstate").exists():
        step("Removing Terraform state (all resources)")
        result = run(
            ["terraform", "state", "list"],
            cwd=env_dir,
            capture=True,
        )
        for line in result.stdout.strip().splitlines():
            addr = line.strip()
            if addr:
                run(["terraform", "state", "rm", addr], cwd=env_dir)

    step("Terraform init")
    run(["terraform", "init"], cwd=env_dir)

    step("Terraform apply")
    cmd = ["terraform", "apply"]
    if auto_approve:
        cmd.append("-auto-approve")
    run(cmd, cwd=env_dir)


def update_kubeconfig(env: str) -> None:
    step("Updating kubeconfig")
    region = get_terraform_output("region", env)
    cluster_name = get_terraform_output("cluster_name", env)
    run(["aws", "eks", "update-kubeconfig", "--name", cluster_name, "--region", region])


def apply_manifests(env: str) -> None:
    step("Applying Confluent manifests")
    overlay = repo_root() / "manifests" / "overlays" / env
    if not overlay.is_dir():
        raise SystemExit(f"Manifests overlay not found: {overlay}")
    run(["kubectl", "apply", "-k", str(overlay)])

    step("Waiting for Zookeeper (3 replicas)")
    run(
        [
            "kubectl", "wait",
            "--for=jsonpath={.status.readyReplicas}=3",
            "statefulset/zookeeper",
            "-n", "confluent",
            "--timeout=300s",
        ]
    )
    time.sleep(60)
    step("Waiting for Kafka (3 replicas)")
    run(
        [
            "kubectl", "wait",
            "--for=jsonpath={.status.readyReplicas}=3",
            "statefulset/kafka",
            "-n", "confluent",
            "--timeout=300s",
        ]
    )


def create_kafka_dns(env: str, zone_id: str, namespace: str, domain: str) -> None:
    step("Creating Route 53 CNAME records for Kafka")
    if not zone_id:
        raise SystemExit("kafka_dns_zone_id not available from Terraform output")

    result = run(
        ["kubectl", "get", "svc", "-n", namespace, "-o", "json"],
        capture=True,
    )
    data = json.loads(result.stdout)

    records: dict[str, str] = {}
    for item in data.get("items", []):
        name = item.get("metadata", {}).get("name", "")
        ingress = item.get("status", {}).get("loadBalancer", {}).get("ingress") or []
        if not ingress:
            continue
        hostname = ingress[0].get("hostname") or ingress[0].get("ip", "")
        hostname = hostname.replace("\r", "").replace("\n", "").strip()
        if not hostname:
            continue
        if "bootstrap" in name:
            records["kafka"] = hostname
        elif "controlcenter" in name:
            records["controlcenter"] = hostname
        else:
            # CFK uses kafka-0, kafka-1, kafka-2 or kafka-0-lb, kafka-1-lb, kafka-2-lb
            for i in range(10):
                if name in (f"kafka-{i}-lb", f"kafka-{i}"):
                    records[f"b{i}"] = hostname
                    break

    if not records:
        print("WARNING: No LoadBalancer hostnames found. Wait for services to get EXTERNAL-IP and retry.")
        print("  kubectl get svc -n confluent")
        return

    domain = domain.rstrip(".")
    changes = []
    for dns_name in ["kafka", "b0", "b1", "b2", "controlcenter"]:
        if dns_name not in records:
            continue
        target = records[dns_name]
        if not target.endswith("."):
            target += "."
        full_name = f"{dns_name}.{domain}."
        changes.append({
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": full_name,
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [{"Value": target}],
            },
        })
        print(f"  {full_name} -> {target}")

    if not changes:
        print("No records to create.")
        return

    # Inline JSON avoids file path and stdin issues on Windows/Git Bash
    batch_json = json.dumps({"Changes": changes})
    subprocess.run(
        [
            "aws", "route53", "change-resource-record-sets",
            "--hosted-zone-id", zone_id,
            "--change-batch", batch_json,
        ],
        check=True,
    )
    print(f"Done. Kafka bootstrap: kafka.{domain}:9092 | Control Center: http://controlcenter.{domain}:9021")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Provision terraform-aws-confluent-platform infrastructure",
        epilog="Prerequisites: terraform, aws CLI, kubectl. AWS credentials configured.",
    )
    parser.add_argument(
        "--env",
        default="dev",
        choices=["dev", "staging"],
        help="Environment (default: dev)",
    )
    parser.add_argument(
        "--remove-state",
        action="store_true",
        help="Remove previous Terraform state",
    )
    parser.add_argument(
        "--auto-approve",
        action="store_true",
        help="Skip Terraform apply confirmation",
    )
    parser.add_argument(
        "--skip-dns",
        action="store_true",
        help="Skip Route 53 DNS record creation",
    )
    parser.add_argument(
        "--skip-manifests",
        action="store_true",
        help="Skip kubectl apply (Terraform only)",
    )
    parser.add_argument(
        "--dns-namespace",
        default="confluent",
        help="Kubernetes namespace for Kafka services (default: confluent)",
    )
    parser.add_argument(
        "--dns-domain",
        default="confluent.local",
        help="DNS domain (default: confluent.local)",
    )
    args = parser.parse_args()

    try:
        provision_terraform(args.env, args.auto_approve, args.remove_state)
        update_kubeconfig(args.env)

        if not args.skip_manifests:
            apply_manifests(args.env)

        if not args.skip_dns:
            zone_id = get_terraform_output("kafka_dns_zone_id", args.env)
            create_kafka_dns(args.env, zone_id, args.dns_namespace, args.dns_domain)

        step("Provisioning complete")
        return 0
    except subprocess.CalledProcessError as e:
        print(f"\nError: command failed with code {e.returncode}", file=sys.stderr)
        if e.stderr:
            print(e.stderr, file=sys.stderr)
        return e.returncode
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
