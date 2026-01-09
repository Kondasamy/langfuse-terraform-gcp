locals {
  langfuse_values   = <<EOT
langfuse:
  replicas: 2
  salt:
    secretKeyRef:
      name: ${kubernetes_secret.langfuse.metadata[0].name}
      key: salt
  nextauth:
    url: "https://${var.domain}"
    secret:
      secretKeyRef:
        name: ${kubernetes_secret.langfuse.metadata[0].name}
        key: nextauth-secret
  serviceAccount:
    annotations:
      iam.gke.io/gcp-service-account: ${google_service_account.langfuse.email}
  additionalEnv:
    - name: LANGFUSE_USE_GOOGLE_CLOUD_STORAGE
      value: "true"
%{for env in var.additional_env~}
    - name: ${env.name}
%{if env.value != null~}
      value: ${jsonencode(env.value)}
%{endif~}
%{if env.valueFrom != null~}
      valueFrom:
%{if env.valueFrom.secretKeyRef != null~}
        secretKeyRef:
          name: ${env.valueFrom.secretKeyRef.name}
          key: ${env.valueFrom.secretKeyRef.key}
%{endif~}
%{if env.valueFrom.configMapKeyRef != null~}
        configMapKeyRef:
          name: ${env.valueFrom.configMapKeyRef.name}
          key: ${env.valueFrom.configMapKeyRef.key}
%{endif~}
%{endif~}
%{endfor~}
  extraVolumeMounts:
    - name: redis-certificate
      mountPath: /var/run/secrets/
      readOnly: true
  extraVolumes:
    - name: redis-certificate
      secret:
        secretName: ${kubernetes_secret.langfuse.metadata[0].name}
        items:
          - key: redis-certificate
            path: redis-ca.crt
  web:
    resources:
      requests:
        cpu: ${var.web_cpu_request}
        memory: ${var.web_memory_request}
      limits:
        cpu: ${var.web_cpu_limit}
        memory: ${var.web_memory_limit}
    livenessProbe:
      initialDelaySeconds: 90
      timeoutSeconds: 15
      periodSeconds: 15
      failureThreshold: 6
    readinessProbe:
      initialDelaySeconds: 45
      timeoutSeconds: 15
      periodSeconds: 10
      failureThreshold: 6
    lifecycle:
      preStop:
        exec:
          command: ["/bin/sh", "-c", "sleep 15"]
  worker:
    resources:
      requests:
        cpu: ${var.worker_cpu_request}
        memory: ${var.worker_memory_request}
      limits:
        cpu: ${var.worker_cpu_limit}
        memory: ${var.worker_memory_limit}
    livenessProbe:
      initialDelaySeconds: 60
      timeoutSeconds: 10
      periodSeconds: 15
      failureThreshold: 6
    readinessProbe:
      initialDelaySeconds: 30
      timeoutSeconds: 10
      periodSeconds: 10
      failureThreshold: 6
postgresql:
  deploy: false
  host: ${google_sql_database_instance.this.private_ip_address}
  auth:
    username: langfuse
    database: langfuse
    existingSecret: ${kubernetes_secret.langfuse.metadata[0].name}
    secretKeys:
      userPasswordKey: postgres-password
clickhouse:
  auth:
    existingSecret: ${kubernetes_secret.langfuse.metadata[0].name}
    existingSecretKey: clickhouse-password
  zookeeper:
    resources:
      requests:
        memory: ${var.zookeeper_memory_request}
        cpu: ${var.zookeeper_cpu_request}
      limits:
        memory: ${var.zookeeper_memory_limit}
        cpu: ${var.zookeeper_cpu_limit}
redis:
  deploy: false
  host: ${google_redis_instance.this.host}
  port: ${google_redis_instance.this.port}
  tls:
    enabled: true
    caPath: /var/run/secrets/redis-ca.crt
  auth:
    existingSecret: ${kubernetes_secret.langfuse.metadata[0].name}
    existingSecretPasswordKey: redis-password
s3:
  deploy: false
  storageProvider: "gcs"
  bucket: ${google_storage_bucket.langfuse.name}
  eventUpload:
    prefix: "events/"
  batchExport:
    prefix: "exports/"
  mediaUpload:
    prefix: "media/"
EOT
  ingress_values    = <<EOT
langfuse:
  ingress:
    enabled: true
    className: gce  # Ignored in GCP but required from K8s
    annotations:
      kubernetes.io/ingress.class: gce
      ingress.gcp.kubernetes.io/pre-shared-cert: ${var.name}
      networking.gke.io/v1beta1.FrontendConfig: https-redirect
    hosts:
    - host: ${var.domain}
      paths:
      - path: /
        pathType: Prefix
  service:
    annotations:
      cloud.google.com/backend-config: '{"default": "langfuse-web"}'
  securityContext:
    allowPrivilegeEscalation: false
EOT
  encryption_values = !var.use_encryption_key ? "" : <<EOT
langfuse:
  encryptionKey:
    secretKeyRef:
      name: ${kubernetes_secret.langfuse.metadata[0].name}
      key: encryption_key
EOT
}

# Service account for workload identity
resource "google_service_account" "langfuse" {
  account_id   = var.name
  display_name = local.tag_name
}

resource "google_service_account_iam_binding" "workload_identity_binding" {
  service_account_id = google_service_account.langfuse.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${data.google_client_config.current.project}.svc.id.goog[${kubernetes_namespace.langfuse.metadata[0].name}/langfuse]"
  ]
}

resource "google_service_account_iam_member" "langfuse_token_creator" {
  service_account_id = google_service_account.langfuse.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.langfuse.email}"
}

resource "kubernetes_namespace" "langfuse" {
  metadata {
    name = var.kubernetes_namespace
  }
}

resource "random_bytes" "salt" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> SALT
  length = 32
}

resource "random_bytes" "nextauth_secret" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> NEXTAUTH_SECRET
  length = 32
}

resource "random_bytes" "encryption_key" {
  count = var.use_encryption_key ? 1 : 0
  # Must be exactly 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> ENCRYPTION_KEY
  length = 32
}

resource "kubernetes_secret" "langfuse" {
  metadata {
    name      = "langfuse"
    namespace = kubernetes_namespace.langfuse.metadata[0].name
  }

  data = {
    "redis-password"      = google_redis_instance.this.auth_string
    "redis-certificate"   = google_redis_instance.this.server_ca_certs[0].cert
    "postgres-password"   = random_password.postgres_password.result
    "salt"                = random_bytes.salt.base64
    "nextauth-secret"     = random_bytes.nextauth_secret.base64
    "clickhouse-password" = random_password.clickhouse_password.result
    "encryption_key"      = var.use_encryption_key ? random_bytes.encryption_key[0].hex : ""
  }
}

# BackendConfig for GCP Load Balancer health check settings
# This aligns GCP health checks with Kubernetes probe settings to prevent
# premature unhealthy markings during pod startup or slow responses
resource "kubernetes_manifest" "langfuse_backend_config" {
  manifest = {
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = "langfuse-web"
      namespace = kubernetes_namespace.langfuse.metadata[0].name
    }
    spec = {
      healthCheck = {
        checkIntervalSec   = 15
        timeoutSec         = 15
        healthyThreshold   = 1
        unhealthyThreshold = 5
        type               = "HTTP"
        requestPath        = "/api/public/ready"
        port               = 3000
      }
      connectionDraining = {
        drainingTimeoutSec = 30
      }
    }
  }

  depends_on = [kubernetes_namespace.langfuse]
}

resource "helm_release" "langfuse" {
  name       = "langfuse"
  repository = "https://langfuse.github.io/langfuse-k8s"
  version    = var.langfuse_chart_version
  chart      = "langfuse"
  namespace  = kubernetes_namespace.langfuse.metadata[0].name

  values = [
    local.langfuse_values,
    local.ingress_values,
    local.encryption_values,
  ]

  depends_on = [
    kubernetes_secret.langfuse,
    google_service_account.langfuse,
    kubernetes_manifest.langfuse_backend_config,
  ]

  timeout = 1800 # Increase timeout to 15 minutes
}

resource "kubernetes_pod_disruption_budget_v1" "langfuse_web" {
  metadata {
    name      = "langfuse-web"
    namespace = kubernetes_namespace.langfuse.metadata[0].name
  }

  spec {
    min_available = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name"      = "langfuse"
        "app.kubernetes.io/component" = "web"
      }
    }
  }

  depends_on = [helm_release.langfuse]
}

# Horizontal Pod Autoscaler for web deployment
resource "kubernetes_horizontal_pod_autoscaler_v2" "langfuse_web" {
  metadata {
    name      = "langfuse-web"
    namespace = kubernetes_namespace.langfuse.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "langfuse-web"
    }

    min_replicas = var.web_min_replicas
    max_replicas = var.web_max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Min"
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }
      scale_up {
        stabilization_window_seconds = 60
        select_policy                = "Max"
        policy {
          type           = "Pods"
          value          = 2
          period_seconds = 60
        }
      }
    }
  }

  depends_on = [helm_release.langfuse]
}

# Horizontal Pod Autoscaler for worker deployment
resource "kubernetes_horizontal_pod_autoscaler_v2" "langfuse_worker" {
  metadata {
    name      = "langfuse-worker"
    namespace = kubernetes_namespace.langfuse.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "langfuse-worker"
    }

    min_replicas = var.worker_min_replicas
    max_replicas = var.worker_max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Min"
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }
      scale_up {
        stabilization_window_seconds = 60
        select_policy                = "Max"
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }
    }
  }

  depends_on = [helm_release.langfuse]
}
