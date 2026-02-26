# terraform-aws-confluent-platform

Reusable Terraform and manifests for **provisioning Confluent Platform (Kafka) on AWS EKS**. Maintained as a shared module; teams use it to create and run Kafka clusters with Zookeeper, external access via internal NLB, and Confluent for Kubernetes (CFK).

---

## For teams: provisioning a Kafka cluster

Use this repo to stand up an EKS cluster and Confluent Platform (Zookeeper + Kafka) that you can connect to from EC2 or pods in the same VPC.

### Option A – Single Python script (recommended)

Prerequisites: **terraform**, **aws CLI**, **kubectl** on PATH. AWS credentials configured.

```bash
git clone <this-repo-url>
cd terraform-aws-confluent-platform

# Configure envs/dev/terraform.tfvars if needed (region, name, etc.)

python scripts/provision.py --auto-approve
```

This runs terraform init/apply, updates kubeconfig, applies Confluent manifests, waits for Zookeeper and Kafka, and creates Route 53 CNAME records. Use `--skip-dns` to omit the DNS step, or `--skip-manifests` for Terraform only. Run `python scripts/provision.py --help` for options.

---

### Option B – Manual steps (copy/paste)

1. **Clone and enter the repo**

   ```bash
   git clone <this-repo-url>
   cd terraform-aws-confluent-platform
   ```

2. **Pin to a release (recommended)**

   Check out a tag so upgrades are explicit:

   ```bash
   git checkout v1.0.0
   ```

3. **Configure the dev environment**

   ```bash
   cd envs/dev
   cp terraform.tfvars.example terraform.tfvars  # if present; otherwise create terraform.tfvars
   # Edit terraform.tfvars: set region, name (e.g. confluent-dev), cluster_version, etc.
   # See variables.tf in this dir for all options.
   ```

4. **Deploy network, EKS, and CFK operator**

   ```bash
   terraform init
   terraform apply
   ```

5. **Apply Confluent CRs (Zookeeper + Kafka)**

   From the **repo root**:

   ```bash
   cd ../..    # back to terraform-aws-confluent-platform/
   aws eks update-kubeconfig --name confluent-dev-eks --region us-east-1
   kubectl apply -k manifests/overlays/dev
   kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 statefulset/zookeeper -n confluent --timeout=300s
   kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 statefulset/kafka -n confluent --timeout=300s
   ```

   - The cluster name comes from the `name` variable (e.g. `confluent-dev` → `confluent-dev-eks`).
   - For more details or different environments, see [manifests/README.md](manifests/README.md).

6. **DNS so pods and EC2 in the VPC can resolve Kafka and Control Center (recommended)**

   Terraform creates a Route 53 private hosted zone for `confluent.local` (variable `kafka_dns_domain`). After Kafka and Control Center are running and their LoadBalancer services have external hostnames (check with `kubectl get svc -n confluent`), run this script once so `kafka.confluent.local`, `b0/b1/b2.confluent.local`, and `controlcenter.confluent.local` resolve in the VPC.

   **Prerequisites:** `kubectl` (context set to your EKS cluster), `jq`, AWS CLI, and bash (e.g. Git Bash on Windows).

   From **repo root**:

   ```bash
   ZONE_ID=$(terraform -chdir=envs/dev output -raw kafka_dns_zone_id)
   ZONE_ID=$ZONE_ID ./scripts/create-kafka-dns.sh
   ```

   Or use the Python provisioner which creates DNS records automatically.

7. **Access Control Center** (view topics, inspect messages)

   From within the VPC: `http://controlcenter.confluent.local:9021` (after running the DNS script).

   From anywhere via port-forward:
   ```bash
   kubectl port-forward controlcenter-0 9021:9021 -n confluent
   ```
   Then open http://localhost:9021

8. **Get Kafka bootstrap for producers/consumers**

   ```bash
   kubectl get svc -n confluent -l type=kafka
   ```

   Use the bootstrap LoadBalancer hostname and port **9092**. With the DNS script and default domain, you can use:

   - `kafka.confluent.local:9092` as `bootstrap.servers` from any pod or EC2 in the same VPC.

   If you customize the `kafka_dns_domain` variable, set the same domain in `manifests/base/kafka.yaml` (under `listeners.external.loadBalancer.domain`) and re-apply the overlay so Kafka advertises the same domain the script uses for Route 53.

### Option B – Add your own environment

- Add a new dir under `envs/` (e.g. `envs/staging`) with its own `main.tf`, `variables.tf`, `providers.tf`, and tfvars.
- Reuse the same modules: `modules/network`, `modules/eks`, `modules/cfk`.
- Add or copy a Kustomize overlay under `manifests/overlays/` (e.g. `staging`) and set the namespace and any patches for that environment.

### Pinning to a release

Consumers should pin to a **git tag** (e.g. `v1.0.0`) so they get predictable behavior and can upgrade when you cut a new release.

---

## Layout

- **Terraform (infra + operator)**
  - `versions.tf` – Terraform and provider constraints.
  - `modules/network` – VPC, subnets, NAT.
  - `modules/eks` – EKS (terraform-aws-modules/eks), EBS CSI addon (Pod Identity), eks-pod-identity-agent.
  - `modules/cfk` – CFK operator only (namespace + Helm). No Kafka/Zookeeper CRs.
  - `envs/dev` – Example environment (network → EKS → CFK operator).
- **Manifests (CFK CRs – applied outside Terraform)**
  - `manifests/base/` – Shared Zookeeper + Kafka CRs. `manifests/overlays/dev` and `overlays/staging` set namespace and optional patches. Apply with `kubectl apply -k manifests/overlays/<env>` or GitOps.

## Why Terraform for infra only?

Terraform owns VPC, EKS, addons, and the CFK operator. Kafka/Zookeeper CRs live in plain YAML and are applied via kubectl or GitOps. This avoids Terraform Kubernetes provider issues and keeps a clear split: infra in Terraform, app CRs in Git.

## Troubleshooting

- **Pods Pending / unbound PVCs** – Ensure the EBS CSI addon is installed and StorageClass `ebs-csi-default-sc` exists. Adjust `spec.storageClass.name` in manifests if your cluster uses another default. Delete stuck CRs and PVCs, then re-apply manifests.
- **Kafka not starting** – Check `kubectl get pods -n <namespace>`, `kubectl describe pod -n <namespace> <name>`, and operator logs: `kubectl logs -n <namespace> -l app.kubernetes.io/name=confluent-operator --tail=100`.

---

## For the maintainer

You own this repo and release it for the team. See **[MAINTAINING.md](MAINTAINING.md)** for versioning, release process, and what to maintain.
