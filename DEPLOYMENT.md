# Langfuse GCP Deployment Guide

This guide provides step-by-step instructions for deploying Langfuse on Google Cloud Platform (GCP) using Terraform.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Terraform Configuration](#terraform-configuration)
4. [Deployment Steps](#deployment-steps)
5. [DNS Configuration](#dns-configuration)
6. [SSL Certificate Troubleshooting](#ssl-certificate-troubleshooting)
7. [Application Configuration](#application-configuration)
8. [Google SSO Setup](#google-sso-setup)
9. [Changing Domain](#changing-domain)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

- **Terraform** >= 1.0
- **gcloud CLI** (Google Cloud SDK)
- **kubectl** (Kubernetes CLI)
- **helm** >= 2.5

### GCP Requirements

1. **Google Cloud Project** with billing enabled
2. **Required APIs Enabled**:
   - Certificate Manager API
   - Cloud DNS API
   - Compute Engine API
   - Container File System API
   - Google Cloud Memorystore for Redis API
   - Kubernetes Engine API
   - Network Connectivity API
   - Service Networking API

   Enable APIs using:
   ```bash
   gcloud services enable \
     certificatemanager.googleapis.com \
     dns.googleapis.com \
     compute.googleapis.com \
     containerfilesystem.googleapis.com \
     redis.googleapis.com \
     container.googleapis.com \
     networkconnectivity.googleapis.com \
     servicenetworking.googleapis.com
   ```

3. **Domain Name** under your control (e.g., `langfuse.example.com`)

4. **GCP Authentication**:
   ```bash
   gcloud auth application-default login
   ```

---

## Initial Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd langfuse-terraform-gcp
```

### 2. Navigate to Quickstart Example

```bash
cd examples/quickstart
```

### 3. Configure Your Domain

Edit `quickstart.tf` and update the `domain` variable:

```hcl
module "langfuse" {
  source = "../.."
  
  domain = "your-domain.com"  # Change this to your domain
  
  # ... rest of configuration
}
```

### 4. Configure Google Provider

Add or update the Google provider configuration in `quickstart.tf`:

```hcl
provider "google" {
  project = "your-gcp-project-id"  # Your GCP project ID
  region  = "us-central1"          # Your preferred region
}
```

**Alternative**: Set via environment variables:
```bash
export GOOGLE_PROJECT="your-gcp-project-id"
export GOOGLE_REGION="us-central1"
```

Or use gcloud default:
```bash
gcloud config set project your-gcp-project-id
```

---

## Terraform Configuration

### Complete Example Configuration

Here's a complete `quickstart.tf` example:

```hcl
module "langfuse" {
  source = "../.."

  domain = "lf.layerpath.dev"

  # Optional: Use a different name for your installation
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
  langfuse_chart_version = "1.5.9"

  # Optional: Additional environment variables
  additional_env = [
    {
      name  = "LOG_LEVEL"
      value = "info"
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
  project = "your-gcp-project-id"
  region  = "us-central1"
}
```

---

## Deployment Steps

### Step 1: Initialize Terraform

```bash
cd examples/quickstart
terraform init
```

This will:
- Download required providers (google, kubernetes, helm)
- Initialize the local module reference

**Troubleshooting**: If you get an error about missing project, ensure the `provider "google"` block is configured correctly.

### Step 2: Create DNS Zone and GKE Cluster (Initial Deployment)

Apply the DNS zone and GKE cluster first to avoid dependency issues:

```bash
terraform apply \
  --target module.langfuse.google_dns_managed_zone.this \
  --target module.langfuse.google_container_cluster.this
```

This creates:
- Google Cloud DNS managed zone
- GKE (Google Kubernetes Engine) cluster

**Expected Output**: You should see resources being created. Note the DNS zone name (it will be your domain with dots replaced by dashes).

### Step 3: Configure DNS Nameservers

Get the nameservers from the created DNS zone:

```bash
# Replace 'lf-layerpath-dev' with your zone name
# Zone name format: domain with dots replaced by dashes
gcloud dns managed-zones describe lf-layerpath-dev --format="get(nameServers)"
```

**Example Output**:
```
ns-cloud-d1.googledomains.com.
ns-cloud-d2.googledomains.com.
ns-cloud-d3.googledomains.com.
ns-cloud-d4.googledomains.com.
```

Update your domain registrar:
1. Log in to your domain registrar (e.g., Google Domains, Cloudflare, Namecheap)
2. Navigate to DNS settings
3. Update nameservers to the values from the command above
4. Save changes

**Note**: DNS propagation can take 15 minutes to 48 hours (usually 1-2 hours).

### Step 4: Verify DNS Propagation

Check if nameservers are updated:

```bash
dig NS your-domain.com
```

You should see the Google Cloud nameservers listed.

### Step 5: Deploy Full Stack

Once DNS nameservers are configured, deploy the complete stack:

```bash
terraform apply
```

This will create:
- VPC and networking components
- Cloud SQL PostgreSQL instance
- Cloud Memorystore Redis instance
- Cloud Storage bucket
- SSL certificate
- Kubernetes resources
- Langfuse Helm release

**Expected Duration**: 15-30 minutes depending on resource provisioning times.

### Step 6: Verify Deployment

Check deployment status:

```bash
# Check Kubernetes pods
kubectl get pods -n langfuse

# Check ingress
kubectl get ingress -n langfuse

# Check SSL certificate status
gcloud compute ssl-certificates list
```

---

## DNS Configuration

### Verify DNS Records

Check that DNS records are created correctly:

```bash
# List all DNS records
gcloud dns record-sets list --zone=your-zone-name

# Check if domain resolves
dig your-domain.com +short
```

You should see:
- **A record**: Points to the load balancer IP
- **NS records**: Google Cloud nameservers
- **SOA record**: Start of Authority record

### Common DNS Issues

**Issue**: Domain doesn't resolve
- **Solution**: Wait for DNS propagation (can take up to 48 hours)
- **Check**: Verify nameservers are correctly set at your registrar

**Issue**: Wrong IP address
- **Solution**: The A record should point to the GCP load balancer IP
- **Check**: Verify the ingress has received an IP: `kubectl get ingress -n langfuse`

---

## SSL Certificate Troubleshooting

### Check Certificate Status

```bash
gcloud compute ssl-certificates list
```

### Common Certificate Statuses

#### 1. `PROVISIONING`

**Status**: Normal - Certificate is being provisioned
**Action**: Wait 15-20 minutes for provisioning to complete
**Expected**: Status will change to `ACTIVE`

#### 2. `FAILED_NOT_VISIBLE`

**Cause**: Google Cloud cannot verify domain ownership because DNS isn't properly configured

**Diagnosis**:
```bash
# Check if DNS A record exists
gcloud dns record-sets list --zone=your-zone-name

# Check if domain resolves
dig your-domain.com +short

# Verify nameservers
dig NS your-domain.com
```

**Solution**:
1. Ensure DNS nameservers are correctly configured at your registrar
2. Verify the A record exists and points to the load balancer IP
3. Wait 10-15 minutes for DNS propagation
4. Recreate the certificate:
   ```bash
   terraform apply -replace=module.langfuse.google_compute_managed_ssl_certificate.this
   ```

#### 3. `FAILED_CAA_CHECKING`

**Cause**: CAA (Certificate Authority Authorization) records don't allow Google's CA

**Diagnosis**:
```bash
# Check for CAA records
dig CAA your-domain.com
dig CAA subdomain.your-domain.com
```

**Solution**:

**Option 1**: Add Google's CA to CAA records (Recommended)
```bash
# Add CAA record allowing Google's CA
gcloud dns record-sets create your-domain.com. \
  --zone=your-zone-name \
  --type=CAA \
  --ttl=300 \
  --rrdatas='0 issue "pki.goog"'
```

**Option 2**: Remove conflicting CAA records if they exist

**After fixing CAA**:
```bash
# Recreate the certificate
terraform apply -replace=module.langfuse.google_compute_managed_ssl_certificate.this
```

#### 4. `ACTIVE`

**Status**: Certificate is active and ready
**Action**: None required - HTTPS should work

### Certificate Provisioning Timeline

- **DNS Propagation**: 15 minutes - 48 hours (usually 1-2 hours)
- **Certificate Verification**: 10-30 minutes after DNS is correct
- **Certificate Provisioning**: ~20 minutes after verification succeeds

**Total Expected Time**: 30-60 minutes after DNS is properly configured

---

## Application Configuration

### Access Langfuse UI

Once deployment is complete, access Langfuse at:
```
https://your-domain.com
```

### Configure Environment Variables

The module supports adding custom environment variables via the `additional_env` parameter:

```hcl
module "langfuse" {
  # ... other configuration ...
  
  additional_env = [
    # Logging configuration
    {
      name  = "LOG_LEVEL"
      value = "info"  # Options: debug, info, warn, error
    },
    
    # UI Customization (Enterprise features)
    {
      name  = "LANGFUSE_UI_FEEDBACK_HREF"
      value = "https://your-feedback-url.com"
    },
    {
      name  = "LANGFUSE_UI_DOCUMENTATION_HREF"
      value = "https://your-docs-url.com"
    },
    
    # Batch export settings
    {
      name  = "BATCH_EXPORT_PAGE_SIZE"
      value = "500"
    },
    {
      name  = "BATCH_EXPORT_ROW_LIMIT"
      value = "1500000"
    },
  ]
}
```

### Using Kubernetes Secrets for Sensitive Values

For sensitive configuration values, use Kubernetes secrets:

**1. Create the secret**:
```bash
kubectl create secret generic langfuse-config \
  --from-literal=api-key=your-secret-value \
  -n langfuse
```

**2. Reference in Terraform**:
```hcl
additional_env = [
  {
    name = "SOME_API_KEY"
    valueFrom = {
      secretKeyRef = {
        name = "langfuse-config"
        key  = "api-key"
      }
    }
  }
]
```

**3. Apply changes**:
```bash
terraform apply
```

### Common Configuration Options

| Variable | Description | Default |
|----------|-------------|---------|
| `LOG_LEVEL` | Logging level | - |
| `LANGFUSE_UI_FEEDBACK_HREF` | Custom feedback link | - |
| `LANGFUSE_UI_DOCUMENTATION_HREF` | Custom documentation link | - |
| `BATCH_EXPORT_PAGE_SIZE` | Page size for S3 exports | 500 |
| `BATCH_EXPORT_ROW_LIMIT` | Max rows per export | 1,500,000 |

**Note**: The module automatically configures:
- `LANGFUSE_USE_GOOGLE_CLOUD_STORAGE=true`
- Database connection (PostgreSQL)
- Redis connection
- Storage bucket (GCS)

---

## Google SSO Setup

### Step 1: Create Google OAuth Credentials

1. **Go to Google Cloud Console**:
   - Navigate to [Google Cloud Console](https://console.cloud.google.com/)
   - Select your project

2. **Enable Google+ API**:
   - Go to **APIs & Services** → **Library**
   - Search for "Google+ API" and enable it

3. **Create OAuth 2.0 Credentials**:
   - Go to **APIs & Services** → **Credentials**
   - Click **Create Credentials** → **OAuth client ID**
   - Application type: **Web application**
   - Name: `Langfuse`
   - **Authorized redirect URIs**: 
     ```
     https://your-domain.com/api/auth/callback/google
     ```
   - Click **Create**

4. **Save Credentials**:
   - Copy the **Client ID** and **Client Secret**
   - Keep these secure - you'll need them in the next step

### Step 2: Create Kubernetes Secret

Create a Kubernetes secret with your OAuth credentials:

```bash
kubectl create secret generic langfuse-google-oauth \
  --from-literal=client-id=YOUR_CLIENT_ID \
  --from-literal=client-secret=YOUR_CLIENT_SECRET \
  -n langfuse
```

**Replace**:
- `YOUR_CLIENT_ID`: Your Google OAuth Client ID
- `YOUR_CLIENT_SECRET`: Your Google OAuth Client Secret

### Step 3: Configure Terraform

Add Google OAuth configuration to your `quickstart.tf`:

```hcl
module "langfuse" {
  source = "../.."
  
  domain = "your-domain.com"
  # ... other configuration ...
  
  additional_env = [
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
    },
    
    # Optional: Restrict to specific domain
    {
      name  = "AUTH_GOOGLE_DOMAIN"
      value = "yourcompany.com"  # Only allow @yourcompany.com emails
    }
  ]
}
```

### Step 4: Apply Configuration

```bash
terraform apply
```

This will update the Langfuse deployment with Google OAuth configuration.

### Step 5: Verify Google SSO

1. **Access Langfuse**: Navigate to `https://your-domain.com`
2. **Check Login Page**: You should see a "Sign in with Google" button
3. **Test Authentication**: Click the button and authenticate with a Google account

### Troubleshooting Google SSO

**Issue**: "Sign in with Google" button doesn't appear
- **Check**: Verify the secret exists: `kubectl get secret langfuse-google-oauth -n langfuse`
- **Check**: Verify environment variables: `kubectl exec -n langfuse <pod-name> -- env | grep AUTH_GOOGLE`
- **Check**: Review pod logs: `kubectl logs -n langfuse -l app.kubernetes.io/name=langfuse`

**Issue**: Redirect URI mismatch error
- **Solution**: Ensure the redirect URI in Google Cloud Console exactly matches: `https://your-domain.com/api/auth/callback/google`

**Issue**: Authentication fails
- **Check**: Verify the Client ID and Client Secret are correct
- **Check**: Ensure the Google+ API is enabled
- **Check**: Verify the domain restriction (if set) matches your email domain

---

## Changing Domain

If you need to change the domain after initial deployment:

### Important Considerations

Changing the domain will affect:
- **DNS managed zone**: Destroyed and recreated
- **DNS record set**: Destroyed and recreated
- **SSL certificate**: Replaced
- **Storage bucket**: Destroyed and recreated (if deletion_protection is false)
- **Helm release**: Updated with new domain

**⚠️ Warning**: If `deletion_protection` is `false`, the storage bucket will be destroyed. Back up any data before changing domains.

### Steps to Change Domain

1. **Backup Data** (if needed):
   ```bash
   # If you have important data in the storage bucket
   gsutil -m cp -r gs://old-bucket-name/* gs://backup-bucket/
   ```

2. **Update Domain in Terraform**:
   Edit `quickstart.tf`:
   ```hcl
   module "langfuse" {
     source = "../.."
     
     domain = "new-domain.com"  # Change this
     # ... rest of configuration
   }
   ```

3. **Review Changes**:
   ```bash
   terraform plan
   ```
   
   Review the plan carefully. You should see:
   - Old DNS zone being destroyed
   - New DNS zone being created
   - SSL certificate being replaced
   - Storage bucket being destroyed/recreated (if deletion_protection is false)

4. **Apply Changes**:
   ```bash
   terraform apply
   ```

5. **Configure New DNS Nameservers**:
   ```bash
   # Get new nameservers
   gcloud dns managed-zones describe new-zone-name --format="get(nameServers)"
   ```
   
   Update your domain registrar with the new nameservers.

6. **Add CAA Record** (if needed):
   ```bash
   gcloud dns record-sets create new-domain.com. \
     --zone=new-zone-name \
     --type=CAA \
     --ttl=300 \
     --rrdatas='0 issue "pki.goog"'
   ```

7. **Wait for DNS Propagation**: 15 minutes - 48 hours

8. **Monitor SSL Certificate**:
   ```bash
   gcloud compute ssl-certificates list
   ```
   
   Wait for status to change to `ACTIVE`.

9. **Clean Up Old DNS Zone** (optional):
   ```bash
   # After verifying new domain works
   gcloud dns managed-zones delete old-zone-name
   ```

---

## Troubleshooting

### Common Issues

#### Issue: "project: required field is not set"

**Error**:
```
Error: Failed to retrieve project, pid: , err: project: required field is not set
```

**Solution**:
1. Add `provider "google"` block to `quickstart.tf`:
   ```hcl
   provider "google" {
     project = "your-gcp-project-id"
     region  = "us-central1"
   }
   ```

2. Or set environment variable:
   ```bash
   export GOOGLE_PROJECT="your-gcp-project-id"
   ```

3. Or use gcloud default:
   ```bash
   gcloud config set project your-gcp-project-id
   ```

#### Issue: Terraform init fails

**Solution**:
- Ensure you're in the `examples/quickstart` directory
- Verify Terraform version: `terraform version` (should be >= 1.0)
- Check network connectivity

#### Issue: Kubernetes provider authentication fails

**Solution**:
- Ensure GKE cluster is created first (Step 2 of deployment)
- Verify cluster credentials: `gcloud container clusters get-credentials cluster-name --region=region`

#### Issue: DNS not resolving

**Solution**:
1. Verify nameservers at registrar match Google Cloud DNS nameservers
2. Check DNS propagation: `dig your-domain.com`
3. Wait for propagation (can take up to 48 hours)

#### Issue: SSL certificate stuck in PROVISIONING

**Solution**:
- Check DNS is correctly configured
- Verify CAA records allow Google's CA
- Wait 20-30 minutes for provisioning
- Check certificate details: `gcloud compute ssl-certificates describe certificate-name`

#### Issue: Langfuse pods not starting

**Solution**:
```bash
# Check pod status
kubectl get pods -n langfuse

# Check pod logs
kubectl logs -n langfuse <pod-name>

# Check events
kubectl get events -n langfuse --sort-by='.lastTimestamp'
```

#### Issue: Cannot access Langfuse UI

**Solution**:
1. Verify ingress has an IP: `kubectl get ingress -n langfuse`
2. Check DNS A record points to ingress IP
3. Verify SSL certificate is ACTIVE
4. Check firewall rules allow traffic

### Useful Commands

```bash
# Check all resources
terraform state list

# Check specific resource
terraform state show module.langfuse.google_dns_managed_zone.this

# View Terraform plan
terraform plan

# View outputs
terraform output

# Check Kubernetes resources
kubectl get all -n langfuse

# Check Helm releases
helm list -n langfuse

# View Langfuse logs
kubectl logs -n langfuse -l app.kubernetes.io/name=langfuse --tail=100

# Check DNS records
gcloud dns record-sets list --zone=zone-name

# Check SSL certificates
gcloud compute ssl-certificates list

# Check GKE cluster
gcloud container clusters describe cluster-name --region=region
```

---

## Additional Resources

- [Langfuse Documentation](https://langfuse.com/docs)
- [Langfuse Self-Hosting Guide](https://langfuse.com/self-hosting/configuration)
- [Langfuse GitHub](https://github.com/langfuse/langfuse)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

---

## Support

For issues or questions:
- Check the [Troubleshooting](#troubleshooting) section
- Review [Langfuse Documentation](https://langfuse.com/docs)
- Join [Langfuse Discord](https://langfuse.com/discord)
- Create an issue in the repository

---

**Last Updated**: November 2025
**Version**: 1.0

