# Infra as Code Repository

This repository serves as the central hub for managing infrastructure as code (IaC), primarily leveraging **Harness** for CI/CD pipelines and **Kubernetes (K8s) with Helm** for application deployments. It encapsulates all configurations and scripts necessary to provision, manage, and deploy applications and their underlying infrastructure.

## Table of Contents

- [Project Overview](#project-overview)
- [Harness CD](#harness-cd)
  - [Initial Setup](#initial-setup)
  - [Connectors](#connectors)
  - [Environments & Infrastructure](#environments--infrastructure)
  - [Deploying a New Service](#deploying-a-new-service)
  - [Pipeline Architecture](#pipeline-architecture)
- [Kubernetes Management](#kubernetes-management)
  - [Cluster Setup](#cluster-setup)
  - [Helm Charts Structure](#helm-charts-structure)
  - [Available Applications](#available-applications)
- [Infrastructure Utilities (misc/)](#infrastructure-utilities-misc)
  - [AWS Spot Instance Manager](#aws-spot-instance-manager)
  - [EBS Volume Management](#ebs-volume-management)
  - [Custom Docker Images](#custom-docker-images)
- [Getting Started](#getting-started)
- [Contribution Guidelines](#contribution-guidelines)

---

## Project Overview

This repository's core purpose is to define and manage infrastructure and deployment processes through code. Key technologies and their roles include:

| Technology | Purpose |
|------------|---------|
| **Harness** | CI/CD automation with GitOps - pipelines sync from this repo |
| **Kubernetes (K3s)** | Container orchestration platform |
| **Helm v3** | Package manager for K8s deployments |
| **AWS Spot Instances** | Cost-effective infrastructure with auto-recovery |
| **Serverless Framework** | Lambda functions for infrastructure automation |
| **Terraform** | IAM and AWS resource provisioning |

---

## Harness CD

Harness configurations are designed to be synchronized with your Harness account, enabling GitOps practices.

### Initial Setup

Before deploying services, you must configure the following:

#### 1. Kubernetes Delegate

Install the Harness Delegate on your K8s cluster (Project Settings → Delegates in Harness UI).

#### 2. GitHub PAT Secret

Create a secret for GitHub access:

```shell
harness secret apply --token YOUR_GITHUB_PAT --secret-name "harness_gitpat"
```

#### 3. Apply Connectors

**GitHub Connector** - Access repositories:

```shell
harness connector --file harness/connector/github-connector.yaml apply --git-user YOUR_USERNAME
```

**Kubernetes Connector** - Access K8s cluster via delegate:

```shell
harness connector --file harness/connector/kubernetes-connector.yaml apply --delegate-name helm-delegate
```

### Connectors

| File | Purpose |
|------|---------|
| `harness/connector/github-connector.yaml` | GitHub repository access using PAT |
| `harness/connector/kubernetes-connector.yaml` | K8s cluster access via delegate |

### Environments & Infrastructure

| File | Description |
|------|-------------|
| `harness/environment/dev-environment.yaml` | Development environment (PreProduction) |
| `harness/environment/dev-infra.yaml` | Infrastructure definition for dev |
| `harness/environment/k8s-single-environment.yaml` | Single K8s environment |
| `harness/environment/k8s-helm-chart-infra.yaml` | Dynamic namespace infrastructure (namespace derived from pipeline variables) |

### Deploying a New Service

Follow these steps to deploy a new application:

```shell
# 1. Create the Harness service
harness service --file harness/cd/whoami/service.yaml apply

# 2. Create environment (if not exists)
harness environment --file harness/environment/dev-environment.yaml apply

# 3. Create infrastructure definition (if not exists)
harness infrastructure --file harness/environment/dev-infra.yaml apply

# 4. Create the deployment pipeline
harness pipeline --file harness/cd/whoami/k8s-rolling-pipeline.yaml apply
```

### Pipeline Architecture

**Simple Rolling Deployment (e.g., whoami)**

```
┌─────────────────────────────────────┐
│  Stage: Deploy                      │
│  ├─ K8sRollingDeploy               │
│  └─ Rollback on Failure            │
└─────────────────────────────────────┘
```

**Multi-Stage Pipeline (e.g., meta)**

```
┌─────────────────────────────────────┐
│  Stage 1: Configuration             │
│  └─ Resolve project variables       │
│     (namespace, branch, paths)      │
├─────────────────────────────────────┤
│  Stage 2: SourceCode                │
│  ├─ Git Clone (with SSH keys)       │
│  └─ Build (pnpm install & build)    │
├─────────────────────────────────────┤
│  Stage 3: Deploy                    │
│  ├─ K8sRollingDeploy               │
│  └─ Rollback on Failure            │
└─────────────────────────────────────┘
```

The meta pipeline uses **pipeline variables** for dynamic configuration:
- `meta_project_name` - Project branch (e.g., `stock`, `binance`)
- `api` / `frontend` - Toggle deployment components
- `num_of_instance` / `num_of_job` - Scaling parameters

---

## Kubernetes Management

### Cluster Setup

Install K3s without Traefik (we use nginx-ingress):

```shell
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
```

Install nginx-ingress controller (Kubernetes version, not F5):

```shell
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

### Helm Charts Structure

Each application chart follows standard Helm structure:

```
k8s/app/<app-name>/
├── Chart.yaml           # Chart metadata & version
├── values.yaml          # Default configuration values
├── README.md            # Application-specific docs
└── templates/
    ├── _helpers.tpl     # Template helpers
    ├── deployment.yaml  # Deployment spec
    ├── service.yaml     # Service spec
    ├── ingress.yaml     # Ingress rules
    ├── hpa.yaml         # Horizontal Pod Autoscaler
    ├── secret.yaml      # Secrets (if needed)
    ├── serviceaccount.yaml
    └── NOTES.txt        # Post-install notes
```

### Available Applications

| Chart | Description |
|-------|-------------|
| `whoami` | Test/healthcheck application |
| `meta` | Main application with StatefulSet support |
| `jmeta` / `metan` | Meta variants |
| `ggg-api` | API service |
| `ggg-brand` | Brand service |
| `ggg-website` | Website frontend |
| `db` | Database deployment |
| `supabase` | Full Supabase stack (Postgres, Auth, Storage, etc.) |
| `splunk-server` | Splunk for logging |
| `fluent-bit` | Log forwarder to Splunk |
| `notion-proxy` | Notion API proxy |
| `supabase-proxy` | Supabase proxy (DaemonSet) |

**Initial Setup Charts** (`k8s/init/`):

| Path | Purpose |
|------|---------|
| `cert-manager/` | Self-signed CA for TLS |
| `dashboard/` | Kubernetes Dashboard setup |
| `harness-cd/` | Namespace for Harness delegate |

---

## Infrastructure Utilities (misc/)

### AWS Spot Instance Manager

A serverless application to manage AWS Spot Fleet instances with automatic Elastic IP assignment and health monitoring.

**Location:** `misc/manage-spot-request/`

#### Components

**Terraform Infrastructure** (`infra/`)

Creates IAM role with permissions for:
- EC2 Spot Fleet management
- Elastic IP association
- DynamoDB access for health state
- CloudWatch Logs

```shell
cd misc/manage-spot-request/infra
terraform init
terraform apply
```

**Lambda Functions** (`aws-python-spot-manager/`)

| Function | Schedule | Purpose |
|----------|----------|---------|
| `checkSpotInstance` | Every 5 min | Assigns Elastic IP to new spot instances |
| `healthcheck` | Every 5 min | Monitors application health, reboots unhealthy instances |
| `toggleHealthcheck` | HTTP API | Enable/disable healthcheck via feature flag |
| `healthStatus` | HTTP API | External health status endpoint |

**Configuration** (in `serverless.yml`):

```yaml
SPOT_FLEET_REQUEST_ID: sfr-xxx          # Your spot fleet ID
ALLOCATION_ID: eipalloc-xxx             # Elastic IP allocation ID
HEALTHCHECK_URL: https://your-app.com   # Primary health endpoint
UNHEALTHY_RESTART_AFTER_SECONDS: 780    # Reboot threshold (13 min)
SLACK_POST_URL: https://...             # Slack notifications
```

**Deploy:**

```shell
cd misc/manage-spot-request/aws-python-spot-manager
serverless deploy --aws-profile ggg
```

#### Health Check Logic

```
┌─────────────────────────────────────────────────┐
│  Check HEALTHCHECK_URL                          │
│  ├─ Healthy? → Update DynamoDB, done           │
│  └─ Unhealthy?                                  │
│      ├─ Age < threshold → Notify Slack, wait   │
│      └─ Age > threshold → Reboot + Notify      │
└─────────────────────────────────────────────────┘
```

### EBS Volume Management

**Location:** `misc/mount-ebs.sh`

Script to manage EBS volume attachment for spot instances:

1. Detects current instance ID
2. Checks if volume is attached elsewhere
3. Detaches from old instance if needed
4. Attaches and mounts to current instance

**Usage:** Called during spot instance bootstrap (user-data).

```shell
# Mount point: /mnt/existing_ebs_volume
# Device: /dev/sdb
```

### Custom Docker Images

**Location:** `misc/docker/`

| Image | Base | Purpose |
|-------|------|---------|
| `node16-yarn/` | Node 16 | Legacy Node.js builds |
| `node20-pnpm/` | Node 20 | Modern Node.js with pnpm |
| `python/` | Python | Python applications |
| `quarkus-jvm-21/` | JVM 21 | Quarkus Java apps |
| `quarkus-micro/` | GraalVM | Native Quarkus builds |
| `splunk-license-server/` | Custom | Splunk licensing |
| `splunk-server/` | Splunk | Full Splunk server |

---

## Getting Started

**Prerequisites:**

| Tool | Required For |
|------|--------------|
| Harness CLI | Pipeline management |
| kubectl | K8s cluster access |
| Helm v3 | Chart deployments |
| AWS CLI | Spot instance management |
| Terraform | IAM provisioning |
| Serverless Framework | Lambda deployments |

**Quick Start:**

1. Set up Harness connectors (see [Initial Setup](#initial-setup))
2. Deploy a test service:

```shell
# Deploy whoami as a test
harness service --file harness/cd/whoami/service.yaml apply
harness pipeline --file harness/cd/whoami/k8s-rolling-pipeline.yaml apply
```

3. Verify deployment:

```shell
kubectl get pods -n default
curl https://whoami.your-domain.com
```

---

## Contribution Guidelines

- **Follow Existing Patterns**: Maintain consistency with existing file structures and naming conventions
- **Test Your Changes**: 
  - Helm: `helm lint` and `helm template` before committing
  - Harness: Test pipeline execution in dev environment
- **Documentation**: Update relevant README files when introducing new components
- **Security**: Never hardcode secrets - use Harness Secrets Management or K8s Secrets
- **Pull Requests**: Provide clear descriptions of changes and their purpose
