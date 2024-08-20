locals {
  name   = var.stack_name
  region = var.aws_region
  tags = {
    Stack = local.name
  }
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  vpc_cidr = "10.0.0.0/16"
}