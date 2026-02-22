# terraform-aws-confluent-platform

Reusable Terraform and manifests for **provisioning Confluent Platform (Kafka) on AWS EKS**. Maintained as a shared module; teams use it to create and run Kafka clusters with Zookeeper, external access via internal NLB, and Confluent for Kubernetes (CFK).

---

## For teams: provisioning a Kafka cluster

Use this repo to stand up an EKS cluster and Confluent Platform (Zookeeper + Kafka) that you can connect to from EC2 or pods in the same VPC.

### Option A – Use the included dev environment

1. **Clone and enter the dev environment**
  ```bash
   git clone <this-repo-url> && cd terraform-aws-confluent-platform/envs/dev
  ```
2. **Pin to a release (recommended)**
  Check out a tag so upgrades are explicit:  
   `git checkout v1.0.0`
3. **Configure**
  - Copy or create `terraform.tfvars` (e.g. `region`, `name`, `cluster_version`).  
  - See `variables.tf` for all options.
4. **Deploy infra and CFK operator**
  ```bash
   terraform init
   terraform apply
  ```
5. **Apply Confluent CRs (Zookeeper + Kafka)**
   
   From the **repo root**, run the following commands to apply the dev overlay using Kustomize and verify that all Kafka and Zookeeper pods are ready:

   ```bash
   kubectl apply -k manifests/overlays/dev
   kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 statefulset/zookeeper -n confluent --timeout=300s
   kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 statefulset/kafka -n confluent --timeout=300s
   ```

   - The cluster name comes from the `name` variable (e.g. `confluent-dev` → `confluent-dev-eks`).
   - For more details or different environments, see [manifests/README.md](manifests/README.md) for full instructions and customization options.
6. **Get Kafka bootstrap for producers/consumers**
  `kubectl get svc -n confluent -l app=kafka`  
   Use the bootstrap LoadBalancer hostname and port 9092. See `manifests/README.md` for DNS and security groups.

7. **DNS so pods and EC2 in the VPC can resolve Kafka (recommended)**  
   Terraform creates a Route 53 private hosted zone for `confluent.local` (variable `kafka_dns_domain`). After Kafka is running and its LoadBalancer services have external hostnames (check with `kubectl get svc -n confluent -l app=kafka`), run the script once so `kafka.confluent.local` and `b0/b1/b2.confluent.local` resolve in the VPC.  
   **Prerequisites:** `kubectl` (context set to your EKS cluster), `jq`, AWS CLI, and bash (e.g. Git Bash on Windows).

   **From repo root:**
   ```bash
   ZONE_ID=$(terraform -chdir=envs/dev output -raw kafka_dns_zone_id)
   ZONE_ID=$ZONE_ID ./scripts/create-kafka-dns.sh
   ```

   **From `envs/dev` (script is also in `envs/dev/scripts/` so you don't need `../`):**
   ```bash
   ZONE_ID=$(terraform output -raw kafka_dns_zone_id)
   ZONE_ID=$ZONE_ID ./scripts/create-kafka-dns.sh
   ```

   Then use **`kafka.confluent.local:9092`** as `bootstrap.servers` from any pod or EC2 in the same VPC. If you customize the `kafka_dns_domain` variable, set the same domain in `manifests/base/kafka.yaml` (under `listeners.external.loadBalancer.domain`) and re-apply the overlay so Kafka advertises the same domain the script uses for Route 53.

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