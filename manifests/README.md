# Confluent Platform manifests (Kustomize)

Zookeeper + Kafka for AWS EKS with **external access via internal NLB**, so clients in the same VPC (EC2, other pods) can publish and consume. Uses **Kustomize** for a base and environment-specific overlays.

- **Base** (`base/`) – Shared Zookeeper and Kafka CRs (no namespace; overlays set it).
- **Overlays** – Per-environment namespace and optional patches:
  - **dev** – namespace `confluent` (matches default CFK operator install from `envs/dev`).
  - **staging** – namespace `confluent-staging`; use as a template for other envs (ensure CFK operator watches that namespace if you use a different one).

Based on [Confluent's external-access-load-balancer example](https://github.com/confluentinc/confluent-kubernetes-examples/blob/master/networking/external-access-load-balancer-deploy/confluent-platform.yaml). Uses **Zookeeper** (not KRaft) and **cp-server** 7.9.0.

## Apply (from repo root)

1. Ensure the CFK operator is installed (`terraform apply` in `envs/dev`).
2. If you previously had KRaft/Kafka in the target namespace, remove them and any bound PVCs first.
3. Apply the desired overlay (e.g. dev):
  ```bash
   kubectl apply -k manifests/overlays/dev
   kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 statefulset/zookeeper -n confluent --timeout=300s
   kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 statefulset/kafka -n confluent --timeout=300s
  ```
   For staging (namespace `confluent-staging`), use namespace `confluent-staging` in the wait commands.
4. Verify pods: `kubectl get pods -n confluent -l app=zookeeper` and `kubectl get pods -n confluent -l app=kafka`.
5. Get Kafka bootstrap: `kubectl get svc -n confluent -l type=kafka`

## Customizing per environment

- **Namespace** – Set in each overlay’s `kustomization.yaml` (`namespace: confluent` or `confluent-staging`). Ensure the CFK operator watches that namespace.
- **Replicas / storage** – Add a patch in the overlay (e.g. `patchesStrategicMerge: [kafka-replicas.yaml]`) and a YAML fragment that overrides `spec.replicas` or `spec.dataVolumeCapacity` for Zookeeper/Kafka.
- **StorageClass** – Patch `spec.storageClass.name` in base or in the overlay.
- **NLB scheme** – Patch Kafka’s `listeners.external.externalAccess.loadBalancer.annotations` (e.g. `internet-facing` for public access).

## Connecting from the same VPC

Kafka is exposed via an **internal** Network Load Balancer. Two options:

- **With DNS (recommended):** Terraform (envs/dev) creates a Route 53 private hosted zone for the Kafka `domain` (e.g. `confluent.local`). After Kafka is up and LoadBalancer services have hostnames, run **`scripts/create-kafka-dns.sh`** once (from repo root or from envs/dev using `envs/dev/scripts/create-kafka-dns.sh`). The script creates CNAMEs for **kafka.confluent.local** (bootstrap) and **b0/b1/b2.confluent.local** (brokers). Clients need all four to resolve; if you see `UnknownHostException` for b0/b1/b2, re-run the script and ensure all Kafka services have EXTERNAL-IP, then retry. Full steps: root [README](../README.md) step 7.
- **Without DNS:** Use the bootstrap LoadBalancer hostname from `kubectl get svc -n confluent -l type=kafka` (e.g. `kafka-bootstrap-xxx.elb.us-east-1.amazonaws.com:9092`). This works for many clients; if you see broker connection issues, set up DNS as above.

## Preview built manifests

```bash
kubectl kustomize manifests/overlays/dev
```

