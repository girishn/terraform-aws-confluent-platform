variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by worker nodes and cluster endpoints."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Optional public subnet IDs, used for public load balancers if needed."
  type        = list(string)
  default     = []
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS cluster API endpoint is publicly accessible."
  type        = bool
  default     = false
}

variable "cluster_endpoint_private_access" {
  description = "Whether the EKS cluster API endpoint is privately accessible."
  type        = bool
  default     = true
}

variable "cluster_enabled_log_types" {
  description = "List of control plane log types to enable for the cluster."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "enable_irsa" {
  description = "Enable IRSA (IAM Roles for Service Accounts). Set to false to use EKS Pod Identity instead."
  type        = bool
  default     = false
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions passed through to the upstream EKS module."
  type        = map(any)
  default     = {}
}

variable "dataplane_wait_duration" {
  description = "Duration to wait after the EKS cluster is active before creating node groups. Use 90s or more so that VPC CNI and other addons can install first; otherwise nodes may stay NotReady."
  type        = string
  default     = "90s"
}

variable "addons" {
  description = "Map of EKS cluster addons to enable. Default enables vpc-cni, coredns, and kube-proxy with before_compute so they install before node groups (required for nodes to become Ready). Set to null to manage addons elsewhere."
  type        = map(any)
  default = {
    vpc-cni = {
      before_compute             = true
      most_recent                = true
      resolve_conflicts_on_create = "OVERWRITE"
    }
    coredns = {
      before_compute = true
      most_recent    = true
    }
    kube-proxy = {
      before_compute = true
      most_recent    = true
    }
  }
}

variable "tags" {
  description = "Additional tags to apply to cluster and node group resources."
  type        = map(string)
  default     = {}
}

