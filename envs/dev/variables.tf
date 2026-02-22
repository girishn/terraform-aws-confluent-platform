variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Base name/prefix for resources."
  type        = string
  default     = "confluent-dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to use for this environment."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.35"
}

variable "cfk_helm_chart_version" {
  description = "Confluent for Kubernetes Helm chart version to deploy. Omit or set to null to use latest. Pin to a version from the repo (e.g. 2.10.0) for reproducibility."
  type        = string
  default     = null
}

variable "ebs_csi_addon_version" {
  description = "Version of the aws-ebs-csi-driver EKS addon. Set to null (default) to use the latest version compatible with cluster_version. Override with a specific version (e.g. v1.35.0-eksbuild.1) if needed."
  type        = string
  default     = null
}

variable "kafka_dns_domain" {
  description = "Private DNS domain for Kafka (e.g. confluent.local). A Route 53 private hosted zone is created for this domain so pods and EC2 in the VPC can resolve kafka.<domain>, b0.<domain>, etc. Must match spec.listeners.external.loadBalancer.domain in manifests/base/kafka.yaml; if you change this variable, update that YAML to the same value (and re-apply manifests), otherwise Kafka will advertise a different domain and DNS will not resolve."
  type        = string
  default     = "confluent.local"
}


