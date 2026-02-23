variable "namespace" {
  description = "Kubernetes namespace where Confluent for Kubernetes operator is deployed."
  type        = string
  default     = "confluent"
}

variable "cfk_helm_release_name" {
  description = "Name of the Helm release for Confluent for Kubernetes."
  type        = string
  default     = "confluent-operator"
}

variable "cfk_helm_chart_name" {
  description = "Name of the Confluent for Kubernetes Helm chart."
  type        = string
  default     = "confluent-for-kubernetes"
}

variable "cfk_helm_chart_version" {
  description = "Version of the Confluent for Kubernetes Helm chart. Set to null to use the latest. Pin (e.g. 2.10.0) for reproducibility."
  type        = string
  default     = null
}

variable "cfk_helm_repo_url" {
  description = "Helm repository URL for Confluent charts."
  type        = string
  default     = "https://packages.confluent.io/helm"
}
