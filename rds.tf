module "rds" {
  source  = "terraform-aws-modules/rds-aurora/aws"

  name           = "${local.name}-db"
  engine         = "aurora-postgresql"
  engine_version = var.rds_engine_version
  instance_class = "db.r6g.large"
  instances = {
    writer = {}
    reader = {}
  }
  vpc_id = module.vpc.vpc_id
  db_subnet_group_name = "${local.name}-db"
  create_db_subnet_group = true
  subnets = module.vpc.private_subnets

  security_group_rules = {
    ingress_vpc = {
      description = "VPC traffic"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }
  apply_immediately   = true

  master_username = var.rds_master_username
  manage_master_user_password_rotation = false

  database_name = "postgres"

  skip_final_snapshot = true
}