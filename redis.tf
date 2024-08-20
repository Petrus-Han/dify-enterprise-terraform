resource "random_password" "redis_secret" {
  length           = 16
  special          = true
  override_special = "/@£$"
}

module "redis" {
  source = "terraform-aws-modules/elasticache/aws"

  replication_group_id     = "${local.name}-redis"
  create_cluster           = false
  create_replication_group = true

  engine_version = var.redis_engine_version
  node_type      = var.redis_node_type
  replicas_per_node_group = var.redis_replicas
  multi_az_enabled = var.redis_multi_az

  maintenance_window = "sun:05:00-sun:09:00"
  apply_immediately  = true

  # Security group
  vpc_id = module.vpc.vpc_id
  security_group_rules = {
    ingress_vpc = {
      description = "VPC traffic"
      cidr_ipv4 = module.vpc.vpc_cidr_block
    }
  }

  # Subnet Group
  subnet_ids = module.vpc.private_subnets

  # Parameter Group
  create_parameter_group = true
  parameter_group_name = "${local.name}-redis-params"
  parameter_group_family = "redis6.x"
  parameters = []

  # Auth
  transit_encryption_enabled = true
  auth_token = random_password.redis_secret.result
}