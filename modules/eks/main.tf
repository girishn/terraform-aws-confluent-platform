module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.15.1"

  name                = var.cluster_name
  kubernetes_version  = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  endpoint_public_access  = true
  endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  enable_irsa = var.enable_irsa

  dataplane_wait_duration = var.dataplane_wait_duration
  addons                 = var.addons

  eks_managed_node_groups = var.eks_managed_node_groups

  tags = var.tags
}
