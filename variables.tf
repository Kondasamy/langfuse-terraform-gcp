variable "name" {
  description = "Name to use for or prefix resources with"
  type        = string
  default     = "langfuse"
}

variable "domain" {
  description = "Domain name used to host langfuse on (e.g., langfuse.company.com)"
  type        = string
}

variable "use_encryption_key" {
  description = "Whether or not to use an Encryption key for LLM API credential and integration credential store"
  type        = bool
  default     = true
}

variable "kubernetes_namespace" {
  description = "Namespace to deploy langfuse to"
  type        = string
  default     = "langfuse"
}

variable "subnetwork_cidr" {
  description = "CIDR block for Subnetwork"
  type        = string
  default     = "10.0.0.0/16"
}

variable "database_instance_tier" {
  description = "The machine type to use for the database instance"
  type        = string
  default     = "db-perf-optimized-N-2"
}

variable "database_instance_edition" {
  description = "The edition of the database instance"
  type        = string
  default     = "ENTERPRISE_PLUS"
}

variable "database_instance_availability_type" {
  description = "The availability type to use for the database instance"
  type        = string
  default     = "REGIONAL"
}

variable "cache_tier" {
  description = "The service tier of the instance"
  type        = string
  default     = "STANDARD_HA"
}

variable "cache_memory_size_gb" {
  description = "Redis memory size in GB"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Whether or not to enable deletion_protection on data sensitive resources"
  type        = bool
  default     = true
}

variable "langfuse_chart_version" {
  description = "Version of the Langfuse Helm chart to deploy"
  type        = string
  default     = "1.5.14"
}

variable "zookeeper_memory_request" {
  description = "Memory request for Zookeeper pods"
  type        = string
  default     = "512Mi"
}

variable "zookeeper_memory_limit" {
  description = "Memory limit for Zookeeper pods"
  type        = string
  default     = "1Gi"
}

variable "zookeeper_cpu_request" {
  description = "CPU request for Zookeeper pods"
  type        = string
  default     = "250m"
}

variable "zookeeper_cpu_limit" {
  description = "CPU limit for Zookeeper pods"
  type        = string
  default     = "500m"
}

variable "additional_env" {
  description = "Additional environment variables to add to the Langfuse container. Supports both direct values and Kubernetes valueFrom references (secrets, configMaps)."
  type = list(object({
    name = string
    # Direct value (mutually exclusive with valueFrom)
    value = optional(string)
    # Kubernetes valueFrom reference (mutually exclusive with value)
    valueFrom = optional(object({
      # Reference to a Secret key
      secretKeyRef = optional(object({
        name = string
        key  = string
      }))
      # Reference to a ConfigMap key
      configMapKeyRef = optional(object({
        name = string
        key  = string
      }))
    }))
  }))
  default = []

  validation {
    condition = alltrue([
      for env in var.additional_env :
      (env.value != null && env.valueFrom == null) || (env.value == null && env.valueFrom != null)
    ])
    error_message = "Each environment variable must have either 'value' or 'valueFrom' specified, but not both."
  }
}

# Web component resource configuration
variable "web_cpu_request" {
  description = "CPU request for web pods"
  type        = string
  default     = "500m"
}

variable "web_cpu_limit" {
  description = "CPU limit for web pods"
  type        = string
  default     = "2"
}

variable "web_memory_request" {
  description = "Memory request for web pods"
  type        = string
  default     = "1Gi"
}

variable "web_memory_limit" {
  description = "Memory limit for web pods"
  type        = string
  default     = "2Gi"
}

variable "web_min_replicas" {
  description = "Minimum number of web pod replicas"
  type        = number
  default     = 2
}

variable "web_max_replicas" {
  description = "Maximum number of web pod replicas"
  type        = number
  default     = 5
}

# Worker component resource configuration
variable "worker_cpu_request" {
  description = "CPU request for worker pods"
  type        = string
  default     = "500m"
}

variable "worker_cpu_limit" {
  description = "CPU limit for worker pods"
  type        = string
  default     = "2"
}

variable "worker_memory_request" {
  description = "Memory request for worker pods"
  type        = string
  default     = "1Gi"
}

variable "worker_memory_limit" {
  description = "Memory limit for worker pods"
  type        = string
  default     = "2Gi"
}

variable "worker_min_replicas" {
  description = "Minimum number of worker pod replicas"
  type        = number
  default     = 2
}

variable "worker_max_replicas" {
  description = "Maximum number of worker pod replicas"
  type        = number
  default     = 4
}
