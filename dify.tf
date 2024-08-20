# Get database username and password from secret manager
data "aws_secretsmanager_secret_version" "dify_db_secret" {
    secret_id = module.rds.cluster_master_user_secret[0].secret_arn
}

# Extract username and password from secret data
locals {
    db_secret = jsondecode(data.aws_secretsmanager_secret_version.dify_db_secret.secret_string)
    db_username = local.db_secret.username
    db_password = local.db_secret.password
    db_host = module.rds.cluster_endpoint
    redis_host = module.redis.replication_group_primary_endpoint_address
    redis_auth = random_password.redis_secret.result
}

resource "kubernetes_namespace" "dify" {
    metadata {
        name = "dify"
    }
}

resource "kubernetes_job" "init_db" {
    metadata {
        name = "init-db"
        namespace = "dify"
    }
    spec {
        template {
            metadata {
                name = "init-db"
            }
            spec {
                container {
                    name = "init-db"
                    image = "postgres:14"
                    env {
                        name = "PGUSER"
                        value = local.db_username
                    }
                    env {
                        name = "PGPASSWORD"
                        value = local.db_password
                    }
                    env {
                        name = "PGHOST"
                        value = local.db_host
                    }
                    env {
                        name = "PGDATABASE"
                        value = "postgres"
                    }
                    command = ["/bin/sh", "-c", "echo \"SELECT 'CREATE DATABASE dify' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'dify')\\gexec\" > /tmp/init.sql && cat /tmp/init.sql | psql"]
                }
                restart_policy = "Never"
            }
        }
        backoff_limit = 4
    }
    depends_on = [module.eks_blueprints_addons, module.rds, kubernetes_namespace.dify]
}

resource "random_password" "dify_secret" {
  length           = 16
  special          = true
  override_special = "/@£$"
}

resource "kubernetes_secret" "dify_secret" {
    metadata {
        name = "dify-secret"
        namespace = "dify"
    }
    data = {
        SECRET_KEY = random_password.dify_secret.result
    }
    depends_on = [kubernetes_namespace.dify]
}

resource "kubernetes_secret" "dify_db_secret" {
    metadata {
        name = "dify-db-secret"
        namespace = "dify"
    }
    data = {
      DB_USERNAME = local.db_username,
      DB_PASSWORD = local.db_password,
      DB_HOST = local.db_host,
      DB_DATABASE = "dify",
      DB_PORT = "5432"
    }
    depends_on = [kubernetes_namespace.dify]
}

resource "kubernetes_secret" "dify_redis_secret" {
    metadata {
        name = "dify-redis-secret"
        namespace = "dify"
    }
    data = {
      CELERY_BROKER_URL = "rediss://:${local.redis_auth}@${local.redis_host}:6379/1"
      BROKER_USE_SSL = "true"
      REDIS_HOST = local.redis_host
      REDIS_DB = "0"
      REDIS_PASSWORD = local.redis_auth
      REDIS_PORT = "6379"
      REDIS_USE_SSL = "true"
    }
    depends_on = [kubernetes_namespace.dify]
}


resource "helm_release" "weaviate" {
    name = "weaviate"
    repository = "https://weaviate.github.io/weaviate-helm"
    chart = "weaviate"
    version = "17.1.1"
    namespace = "dify"
    set {
      name = "storage.storageClassName"
      value = kubernetes_storage_class.ebs-sc.metadata[0].name
    }
    set {
      name = "service.type"
      value = "ClusterIP"
    }
    set {
      name = "grpcService.type"
      value = "ClusterIP"
    }
}

resource "aws_iam_role" "dify_role" {
  name              = "${module.eks.cluster_name}-dify-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  ]
}

resource "kubernetes_service_account" "dify_sa" {
  metadata {
    name = "dify-sa"
    namespace = "dify"
  }
  depends_on = [module.eks_blueprints_addons]
}

# Generate a eks pod identity association for the service account
resource "aws_eks_pod_identity_association" "dify" {
    cluster_name = module.eks.cluster_name
    namespace = "dify"
    service_account = kubernetes_service_account.dify_sa.metadata[0].name
    depends_on = [module.eks_blueprints_addons]
    role_arn = aws_iam_role.dify_role.arn
}


resource "kubernetes_job" "dify_upgrade_db" {
    metadata {
        name = "dify-upgrade-db"
        namespace = "dify"
    }
    spec {
        template {
            metadata {
                name = "dify-upgrade-db"
            }
            spec {
                container {
                    name = "dify-upgrade-db"
                    image = "langgenius/dify-api:${var.dify_version}"
                    env {
                      name = "MODE"
                      value = "api"
                    }
                    env_from {
                      secret_ref {
                        name = kubernetes_secret.dify_db_secret.metadata[0].name
                      }
                    }
                    command = ["/bin/sh", "-c", "flask db upgrade"]
                }
                restart_policy = "Never"
            }
        }
        backoff_limit = 4
    }
    depends_on = [kubernetes_job.init_db]
}

resource "helm_release" "dify" {
    name = "dify"
    repository = "https://douban.github.io/charts/"
    chart = "dify"
    namespace = "dify"
    version = "0.4.1"
    recreate_pods = true
    values = [
    <<EOT
    global:
      host: ${local.ingress_nginx_hostname}
      enableTLS: ${var.dify_enable_tls}
      storageType: "s3"
      image:
        tag: ${var.dify_version}
      extraBackendEnvs:
      - name: SECRET_KEY
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_secret.metadata[0].name}
            key: SECRET_KEY
      - name: LOG_LEVEL
        value: INFO
      - name: S3_ENDPOINT
        value: "https://s3.${local.region}.amazonaws.com"
      - name: S3_BUCKET_NAME
        value: ${module.s3_bucket.s3_bucket_id}
      - name: VECTOR_STORE
        value: weaviate
      - name: WEAVIATE_ENDPOINT
        value: http://weaviate:8080
      - name: WEAVIATE_GRPC_ENABLED
        value: "true"
      - name: DB_USERNAME
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_db_secret.metadata[0].name}
            key: DB_USERNAME
      - name: DB_PASSWORD
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_db_secret.metadata[0].name}
            key: DB_PASSWORD
      - name: DB_HOST
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_db_secret.metadata[0].name}
            key: DB_HOST
      - name: DB_PORT
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_db_secret.metadata[0].name}
            key: DB_PORT
      - name: DB_DATABASE
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_db_secret.metadata[0].name}
            key: DB_DATABASE
      - name: REDIS_HOST
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_redis_secret.metadata[0].name}
            key: REDIS_HOST
      - name: REDIS_PORT
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_redis_secret.metadata[0].name}
            key: REDIS_PORT
      - name: REDIS_DB
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_redis_secret.metadata[0].name}
            key: REDIS_DB
      - name: REDIS_PASSWORD
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_redis_secret.metadata[0].name}
            key: REDIS_PASSWORD
      - name: REDIS_USE_SSL
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_redis_secret.metadata[0].name}
            key: REDIS_USE_SSL
      - name: CELERY_BROKER_URL
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_redis_secret.metadata[0].name}
            key: CELERY_BROKER_URL
      - name: BROKER_USE_SSL
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret.dify_redis_secret.metadata[0].name}
            key: BROKER_USE_SSL
    ingress:
      enabled: true
      className: nginx
    redis:
      embedded: false
    minio:
      embedded: false
    postgresql:
      embedded: false
    serviceAccount:
      create: false
      name: dify-sa
    EOT
    ]

    depends_on = [kubernetes_job.init_db, kubernetes_job.dify_upgrade_db, helm_release.weaviate]
}