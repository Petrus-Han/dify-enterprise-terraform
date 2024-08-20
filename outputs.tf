output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_config" {
  description = "EKS cluster endpoint"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name}"
}

output "redis_primary_endpoint_address" {
  description = "Redis primary endpoint address"
  value       = module.redis.replication_group_primary_endpoint_address
}

output "rds_cluster_endpoint" {
  description = "Aurora PostgreSQL cluster endpoint"
  value       = module.rds.cluster_endpoint
}

output "rds_admin_secret" {
  description = "Admin secret for Aurora PostgreSQL cluster"
  value       = module.rds.cluster_master_user_secret[0].secret_arn
}

output "ingress_hostname" {
  description = "Hostname for nginx ingress"
  value = "http://${local.ingress_nginx_hostname}"
}