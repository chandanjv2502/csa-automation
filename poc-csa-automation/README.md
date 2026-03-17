# CSA Automation POC - Validation Dry Run

## Purpose

This POC validates that the infrastructure requirements documented in `/Users/chandanjv/Documents/NextEra/Freshsetup/Architechture/Requirements.md` are complete and sufficient by building a working prototype that matches the architecture defined in `/Users/chandanjv/Documents/NextEra/Freshsetup/Architechture/design-updated.md`.

## Architecture Overview

**9 Pods (Simplified - No API Gateway):**
1. Frontend UI (React + Nginx web server)
2. Contract Discovery Service
3. Contract Ingestion Service
4. AI Extraction Service
5. CSA Routing Service
6. Siren Load Service
7. Notification Service
8. Mock Phoenix API (POC only)
9. Mock Siren API (POC only)

**Key Features:**
- AWS Load Balancer Controller (manages ALB via Kubernetes Ingress)
- AWS Cognito authentication at ALB level
- All backend services use ClusterIP (internal only)
- IRSA (IAM Roles for Service Accounts) for AWS service access
- Environment-agnostic Docker images (build once, deploy anywhere)

## Directory Structure

```
poc-csa-automation/
├── infrastructure/
│   ├── terraform/          # Terraform configs for AWS resources
│   │   ├── vpc.tf         # VPC, subnets, NAT gateway
│   │   ├── eks.tf         # EKS cluster with OIDC
│   │   ├── rds.tf         # PostgreSQL database
│   │   ├── s3.tf          # S3 bucket for contracts
│   │   ├── sqs.tf         # 5 SQS queues + DLQ
│   │   ├── secrets.tf     # Secrets Manager
│   │   ├── cognito.tf     # Cognito User Pool
│   │   └── iam.tf         # IAM roles for IRSA
│   └── eksctl/
│       └── cluster-config.yaml  # EKS cluster creation config
│
├── helm-charts/
│   └── csa-automation/    # Parent Helm chart
│       ├── Chart.yaml
│       ├── values.yaml    # Environment-agnostic values
│       ├── values-dev.yaml
│       ├── values-uat.yaml
│       ├── values-prod.yaml
│       └── templates/
│           ├── namespace.yaml
│           ├── serviceaccounts.yaml
│           ├── configmap.yaml
│           ├── ingress.yaml
│           ├── deployments/
│           │   ├── frontend.yaml
│           │   ├── contract-discovery.yaml
│           │   ├── contract-ingestion.yaml
│           │   ├── ai-extraction.yaml
│           │   ├── csa-routing.yaml
│           │   ├── siren-load.yaml
│           │   ├── notification.yaml
│           │   ├── mock-phoenix.yaml
│           │   └── mock-siren.yaml
│           └── services/
│               ├── frontend-service.yaml
│               ├── contract-discovery-service.yaml
│               └── ... (all other services)
│
├── docker-images/
│   ├── frontend-ui/
│   │   ├── Dockerfile
│   │   ├── src/           # React app source
│   │   └── nginx.conf
│   ├── contract-discovery/
│   │   ├── Dockerfile
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── contract-ingestion/
│   │   ├── Dockerfile
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── ai-extraction/
│   │   ├── Dockerfile
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── csa-routing/
│   │   ├── Dockerfile
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── siren-load/
│   │   ├── Dockerfile
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── notification-service/
│   │   ├── Dockerfile
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── mock-phoenix-api/
│   │   ├── Dockerfile
│   │   └── main.py
│   └── mock-siren-api/
│       ├── Dockerfile
│       └── main.py
│
├── scripts/
│   ├── 01-setup-aws-resources.sh     # Create all AWS resources
│   ├── 02-build-docker-images.sh     # Build and push to ECR
│   ├── 03-deploy-helm-chart.sh       # Deploy to EKS
│   ├── 04-get-alb-dns.sh            # Retrieve ALB DNS name
│   ├── 05-test-deployment.sh        # End-to-end testing
│   └── 99-cleanup.sh                # Destroy all resources
│
└── docs/
    ├── POC-SETUP.md                  # Setup instructions
    ├── REQUIREMENTS-VALIDATION.md    # Checklist for validating Requirements.md
    └── GAPS-AND-FINDINGS.md          # Document what's missing
```

## Prerequisites

### Local Tools Required
- AWS CLI v2
- kubectl
- Helm 3
- Docker
- eksctl (or Terraform)
- jq (for JSON parsing)

### AWS Account Requirements
- Admin access to AWS account (for POC)
- AWS profile configured: `aws configure --profile csa-poc`

## Quick Start

### Step 1: Create AWS Infrastructure

```bash
cd infrastructure/terraform
terraform init
terraform plan -var-file="poc.tfvars"
terraform apply -var-file="poc.tfvars"
```

This creates:
- VPC with public/private subnets
- EKS cluster with OIDC provider enabled
- RDS PostgreSQL instance
- S3 bucket
- 5 SQS queues + 1 DLQ
- AWS Secrets Manager secrets
- Cognito User Pool
- IAM roles for IRSA
- AWS Load Balancer Controller (installed via Helm)

### Step 2: Build and Push Docker Images

```bash
cd ../../scripts
./02-build-docker-images.sh
```

This:
- Builds all 9 Docker images
- Tags with environment-agnostic version (e.g., `v1.0.0`)
- Pushes to ECR

### Step 3: Deploy Helm Chart

```bash
./03-deploy-helm-chart.sh dev
```

This:
- Deploys all 9 pods to `csa-dev-ns` namespace
- Creates Ingress resource (triggers ALB creation)
- Configures Cognito authentication

### Step 4: Get ALB DNS Name

```bash
./04-get-alb-dns.sh

# Output: k8s-csadevns-abc123.us-east-1.elb.amazonaws.com
```

### Step 5: Test Deployment

```bash
./05-test-deployment.sh
```

This runs end-to-end tests:
- Contract discovery triggers
- PDF ingestion works
- AI extraction completes
- Routing logic works
- Siren load succeeds
- Notifications sent

## Requirements Validation

After POC deployment, validate Requirements.md completeness:

```bash
cd docs
cat REQUIREMENTS-VALIDATION.md
```

This checklist confirms:
- All required GitHub secrets identified
- EKS namespace details complete
- IAM permissions sufficient
- Network access paths verified
- Missing items documented

## Cleanup

```bash
cd scripts
./99-cleanup.sh
```

This destroys all AWS resources to avoid costs.

## Expected Outcomes

### Success Criteria
- All 9 pods running and healthy
- ALB created with Cognito authentication working
- End-to-end flow completes successfully
- Requirements.md validated as complete OR gaps documented

### Deliverables
1. Working POC matching design-updated.md
2. REQUIREMENTS-VALIDATION.md with checklist results
3. GAPS-AND-FINDINGS.md documenting missing requirements
4. Confirmation that Requirements.md is sufficient for NextEra deployment

## Next Steps

Once POC is validated:
1. Update Requirements.md if gaps found
2. Share validated requirements with NextEra (Jeff)
3. Use this POC as reference for NextEra deployment
4. Replicate the same structure in NextEra's AWS account

## Notes

- This POC uses Dsider's AWS account, NOT NextEra's
- Intentionally mimics NextEra's environment constraints
- Build-once-deploy-anywhere pattern validated here
- Same Helm charts will work in NextEra with different `values-*.yaml`
