data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

data "http" "ebs_csi_driver_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/master/docs/example-iam-policy.json"
}

data "http" "efs_csi_driver_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/docs/iam-policy-example.json"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.20"

  cluster_name                   = local.name
  cluster_version                = "1.30"
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
    aws-efs-csi-driver = {
      most_recent = true
    }
  }

  # Give the Terraform identity admin access to the cluster
  # which will allow resources to be deployed into the cluster
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API"

  eks_managed_node_groups = {
    core = {
      instance_types = ["m7g.xlarge"]
      ami_type       = "AL2023_ARM_64_STANDARD"
      min_size       = 3
      max_size       = 3
      desired_size   = 3
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
          }
        }
      }
      labels = {
        "component" = "app"
      }
      iam_role_attach_cni_policy = true
    }

    db = {
      instance_types = ["r7g.xlarge"]
      ami_type       = "AL2023_ARM_64_STANDARD"
      min_size       = 3
      max_size       = 3
      desired_size   = 3
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
          }
        }
      }
      labels = {
        "component" = "db"
      }
      iam_role_attach_cni_policy = true
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver_role" {
  name               = "${module.eks.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
  inline_policy {
    name = "ebs-csi-driver"
    policy = data.http.ebs_csi_driver_policy.response_body
  }
}

resource "aws_eks_pod_identity_association" "ebs_csi_driver" {
    cluster_name = module.eks.cluster_name
    namespace = "kube-system"
    service_account = "ebs-csi-controller-sa"
    role_arn = aws_iam_role.ebs_csi_driver_role.arn
}

resource "aws_iam_role" "efs_csi_driver_role" {
  name               = "${module.eks.cluster_name}-efs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
  inline_policy {
    name = "efs-csi-driver"
    policy = data.http.efs_csi_driver_policy.response_body
  }
}

resource "aws_eks_pod_identity_association" "efs_csi_driver" {
    cluster_name = module.eks.cluster_name
    namespace = "kube-system"
    service_account = "efs-csi-controller-sa"
    role_arn = aws_iam_role.efs_csi_driver_role.arn
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  create_delay_dependencies = [for group in module.eks.eks_managed_node_groups : group.node_group_arn]

  enable_metrics_server     = true
  enable_aws_load_balancer_controller = true
  enable_secrets_store_csi_driver = true
  enable_ingress_nginx = true

  ingress_nginx = {
    values = [yamlencode({
      controller = {
        service = {
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
          }
          loadBalancerClass = "service.k8s.aws/nlb"
        }
      }
    })]
  }

  tags = local.tags
}

resource "kubernetes_storage_class" "ebs-sc" {
  metadata {
    name = "ebs-sc"
  }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
}

data "kubernetes_service" "ingress_nginx_svc" {
  metadata {
    name = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}

locals {
  ingress_nginx_hostname = data.kubernetes_service.ingress_nginx_svc.status[0].load_balancer[0].ingress[0].hostname
}