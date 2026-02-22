output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS region of the EKS cluster."
  value       = var.region
}

output "update_kubeconfig_command" {
  description = "Run this command to add the cluster to your kubeconfig (e.g. for kubectl)."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "kafka_dns_zone_id" {
  description = "Route 53 private hosted zone ID for Kafka DNS. Use with scripts/create-kafka-dns.sh after deploying Kafka so kafka.<domain> and b0/b1/b2.<domain> resolve in the VPC."
  value       = aws_route53_zone.kafka_dns.zone_id
}

output "kafka_dns_zone_name" {
  description = "Private DNS domain name (e.g. confluent.local). Use kafka.<name>:9092 as bootstrap once CNAMEs are created."
  value       = aws_route53_zone.kafka_dns.name
}
