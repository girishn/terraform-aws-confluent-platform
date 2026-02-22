output "namespace" {
  description = "Namespace where Confluent for Kubernetes and components are deployed."
  value       = kubernetes_namespace_v1.confluent.metadata[0].name
}

output "cfk_helm_release_name" {
  description = "Name of the Confluent for Kubernetes Helm release."
  value       = helm_release.cfk.name
}

