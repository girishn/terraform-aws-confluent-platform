module "network" {
  source = "../../modules/network"

  name                = var.name
  vpc_cidr            = var.vpc_cidr
  azs                 = var.azs
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = {
    Environment = "dev"
  }
}

# Private hosted zone for Kafka DNS so pods and EC2 in the VPC can resolve kafka.<domain>, b0.<domain>, etc.
# After deploying Kafka, run scripts/create-kafka-dns.sh to create CNAME records pointing to the NLB hostnames.
resource "aws_route53_zone" "kafka_dns" {
  name = var.kafka_dns_domain

  vpc {
    vpc_id = module.network.vpc_id
  }

  tags = {
    Environment = "dev"
  }
}

module "eks" {
  source = "../../modules/eks"

  cluster_name    = "${var.name}-eks"
  cluster_version = var.cluster_version

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  # Give VPC CNI and other addons time to install before node groups start (avoids NotReady nodes)
  dataplane_wait_duration = "90s"

  addons = {
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
    eks-pod-identity-agent = {
      before_compute = true
      most_recent    = true
    }
  }

  eks_managed_node_groups = {
    default = {
      kubernetes_version = var.cluster_version
      min_size           = 2
      max_size           = 4
      desired_size       = 2

      instance_types = ["t3.medium"]
      disk_size      = 100

      labels = {
        role = "confluent"
      }
    }
  }

  tags = {
    Environment = "dev"
  }
}

# EBS CSI driver IAM role for Pod Identity (not IRSA). The addon uses this role via
# aws_eks_pod_identity_association; the cluster must have the eks-pod-identity-agent addon.
resource "aws_iam_role" "ebs_csi" {
  name = "${module.eks.cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEksPodIdentityToAssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks.cluster_name
  namespace      = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn       = aws_iam_role.ebs_csi.arn
}

# Resolve a supported addon version for this cluster's Kubernetes version (avoids InvalidParameterException).
data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = coalesce(var.ebs_csi_addon_version, data.aws_eks_addon_version.ebs_csi.version)
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # Creates default StorageClass "ebs-csi-default-sc" (GP3) for dynamic provisioning
  configuration_values = jsonencode({
    defaultStorageClass = { enabled = true }
  })

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.ebs_csi,
    aws_eks_pod_identity_association.ebs_csi,
  ]
}

# Use EKS module outputs (not data sources) so provider config is available during plan/refresh.
# Exec-based auth avoids localhost fallback when data sources are deferred.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.region
    ]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        var.region
      ]
    }
  }
}

# CFK operator only. Kafka/KRaftController CRs are in manifests/confluent-dev/ (apply via kubectl or GitOps).
module "cfk" {
  source = "../../modules/cfk"

  providers = {
    kubernetes = kubernetes
    helm       = helm
  }

  namespace             = "confluent"
  cfk_helm_chart_version = var.cfk_helm_chart_version

  depends_on = [aws_eks_addon.ebs_csi]
}
