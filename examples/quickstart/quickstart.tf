module "langfuse" {
  source = "../.."

  domain = "lf.layerpath.dev"

  # Optional use a different name for your installation
  # e.g. when using the module multiple times on the same GCP account
  name = "langfuse"

  # Optional: Configure the Subnetwork
  subnetwork_cidr = "10.0.0.0/16"

  # Optional: Configure the Kubernetes cluster
  kubernetes_namespace = "langfuse"

  # Optional: Configure the database instances
  database_instance_tier              = "db-perf-optimized-N-4"
  database_instance_availability_type = "REGIONAL"
  database_instance_edition           = "ENTERPRISE_PLUS"

  # Optional: Configure the cache
  cache_tier           = "STANDARD_HA"
  cache_memory_size_gb = 1

  # Optional: Configure the Langfuse Helm chart version
  langfuse_chart_version = "1.5.14"

  # Optional: Configure Zookeeper resources (increase for stability)
  zookeeper_memory_request = "512Mi"
  zookeeper_memory_limit   = "1Gi"
  zookeeper_cpu_request    = "250m"
  zookeeper_cpu_limit      = "500m"

  additional_env = [
    # Disable username/password authentication (requires SSO)
    {
      name  = "AUTH_DISABLE_USERNAME_PASSWORD"
      value = "true"
    },
    # Google OAuth Configuration
    {
      name = "AUTH_GOOGLE_CLIENT_ID"
      valueFrom = {
        secretKeyRef = {
          name = "langfuse-google-oauth"
          key  = "client-id"
        }
      }
    },
    {
      name = "AUTH_GOOGLE_CLIENT_SECRET"
      valueFrom = {
        secretKeyRef = {
          name = "langfuse-google-oauth"
          key  = "client-secret"
        }
      }
    },
    {
      name  = "AUTH_GOOGLE_ISSUER"
      value = "https://accounts.google.com"
    },
    {
      name  = "AUTH_GOOGLE_CLIENT_AUTH_METHOD"
      value = "client_secret_post"
    },
    {
      name  = "AUTH_GOOGLE_CHECKS"
      value = "nonce"
    }
  ]
}

provider "kubernetes" {
  host                   = module.langfuse.cluster_host
  cluster_ca_certificate = module.langfuse.cluster_ca_certificate
  token                  = module.langfuse.cluster_token
}

provider "helm" {
  kubernetes {
    host                   = module.langfuse.cluster_host
    cluster_ca_certificate = module.langfuse.cluster_ca_certificate
    token                  = module.langfuse.cluster_token
  }
}

provider "google" {
  project = "layerpath-langfuse"
  region  = "us-central1"
}
