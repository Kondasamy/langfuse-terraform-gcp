# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform module for deploying [Langfuse](https://langfuse.com/) (open-source LLM observability platform) on Google Cloud Platform. It creates a production-ready, secure stack using GCP managed services.

## Common Commands

```bash
# Initialize Terraform
terraform init

# First apply (required due to kubernetes_manifest dependency issue)
terraform apply --target module.langfuse.google_dns_managed_zone.this --target module.langfuse.google_container_cluster.this

# Full deployment
terraform apply

# Format Terraform files
terraform fmt -recursive

# Validate configuration
terraform validate

# Check certificate provisioning status
gcloud compute ssl-certificates list
```

## Architecture

The module creates these interconnected GCP resources:

**Networking (vpc.tf)**
- VPC with private subnet, Cloud Router, and NAT gateway
- Private Service Connection for managed services (Cloud SQL, Redis)
- Internal firewall rules for cluster communication

**Compute (gke.tf)**
- GKE Autopilot cluster with Workload Identity enabled
- VPC-native networking mode

**Data Stores**
- Cloud SQL PostgreSQL 15 (postgres.tf) - primary database with point-in-time recovery
- Cloud Memorystore Redis (redis.tf) - cache with TLS and auth enabled
- ClickHouse (deployed via Helm chart, password in clickhouse.tf) - analytics database
- Cloud Storage bucket (storage.tf) - for events, exports, and media uploads

**Ingress & TLS (tls.tf, dns.tf)**
- Google-managed SSL certificate
- Cloud DNS zone with A record pointing to GKE ingress
- HTTPS redirect via FrontendConfig

**Application (langfuse.tf)**
- Langfuse Helm chart deployment
- Kubernetes secrets for all credentials (Redis, PostgreSQL, ClickHouse, encryption keys)
- Workload Identity binding for GCS access
- Pod Disruption Budget for web component

## Key Design Patterns

**Two-phase apply**: Due to a terraform-provider-kubernetes limitation with `kubernetes_manifest`, DNS zone and GKE cluster must be applied first before the full stack.

**Helm values generation**: The `langfuse.tf` file uses locals to generate YAML values dynamically, injecting resource references (IPs, secrets, bucket names) from Terraform-managed resources.

**Secrets management**: All sensitive values (passwords, auth strings, certificates) flow through a single `kubernetes_secret.langfuse` resource.

**Workload Identity**: The Langfuse service account uses GKE Workload Identity to access GCS without storing credentials.

## Required GCP APIs

Before deploying, enable: Certificate Manager, Cloud DNS, Compute Engine, Container File System, Memorystore for Redis, Kubernetes Engine, Network Connectivity, Service Networking.

## Module Outputs

The module exposes `cluster_host`, `cluster_ca_certificate`, and `cluster_token` for configuring Kubernetes and Helm providers in the consuming Terraform configuration.
