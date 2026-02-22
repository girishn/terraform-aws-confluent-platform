# Confluent for Kubernetes: operator only (namespace + Helm).
# CFK CRs (Kafka, KRaftController, etc.) are managed outside Terraform via GitOps or kubectl
# — see repo root manifests/ and README.

resource "kubernetes_namespace_v1" "confluent" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "cfk" {
  name       = var.cfk_helm_release_name
  repository = var.cfk_helm_repo_url
  chart      = var.cfk_helm_chart_name
  version    = var.cfk_helm_chart_version
  namespace  = var.namespace

  create_namespace = false

  depends_on = [kubernetes_namespace_v1.confluent]
}
