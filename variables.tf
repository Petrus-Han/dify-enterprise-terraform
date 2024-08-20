variable "aws_region" {
  description = "AWS region to create resources"
  default     = "us-west-2"
}

variable "stack_name" {
  description = "Name of the stack"
  default     = "dify"
}

variable "redis_engine_version" {
  description = "Redis engine version"
  default     = "6.2"
}

variable "redis_node_type" {
  description = "Instance type for Redis nodes"
  default     = "cache.r6g.large"
}

variable "redis_replicas" {
  description = "Number of Redis read replicas"
  default     = 1
}

variable "redis_multi_az" {
  description = "Enable multi-AZ for Redis"
  default     = true
}

variable "rds_engine_version" {
  description = "Aurora PostgreSQL engine version"
  default     = "14.9"
}

variable "rds_instance_type" {
  description = "Instance type for RDS instances"
  default     = "r6g.xlarge"
}

variable "rds_reader_count" {
  description = "Number of Aurora PostgreSQL reader instances"
  default     = 1
}


variable "rds_master_username" {
  description = "Username of cluster admin of Aurora PostgreSQL cluster"
  default     = "cluster_admin"
}

variable "dify_version" {
  description = "Version of dify"
  default     = "0.6.16"
}

variable "dify_enable_tls" {
  description = "Enable HTTPS for dify"
  default     = false
}
