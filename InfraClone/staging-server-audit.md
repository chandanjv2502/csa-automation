# Staging-Server Infrastructure Audit

**Date:** 2026-03-23
**Purpose:** Document existing infrastructure in staging-server AWS account before cloning to nextera-clone
**Source Profile:** `staging-server` (Account ID: 524997768738)
**Target Profile:** `nextera-clone` (with $100 credit constraint)
**Region:** us-east-1

---

## 1. EKS Cluster

**Cluster Name:** `csa-poc-eks`
**Kubernetes Version:** 1.31
**OIDC Provider:** `https://oidc.eks.us-east-1.amazonaws.com/id/D710E9122A01B7D29B58FB8A6A511CD6`
**VPC:** vpc-012a60d830a2d3cca
**Security Groups:** sg-0ddb1c708e25897d1

### Node Group: csa-poc-private-nodes
- **Instance Type:** t3.medium
- **Scaling Config:**
  - Min Size: 1
  - Max Size: 4
  - Desired Size: 2
- **AMI Type:** AL2023_x86_64_STANDARD
- **Disk Size:** Default (20GB)

### Subnets
**Total Subnets:** 4 (2 public, 2 private across 2 AZs)

| Subnet ID | CIDR | AZ | Type | Name |
|-----------|------|-----|------|------|
| subnet-0d5df5462d8dd2dca | 10.0.1.0/24 | us-east-1a | Public | nextera-csa-poc-public-us-east-1a |
| subnet-090c9011b660e5ed5 | 10.0.2.0/24 | us-east-1b | Public | nextera-csa-poc-public-us-east-1b |
| subnet-0bfd132951efac411 | 10.0.10.0/24 | us-east-1a | Private | nextera-csa-poc-private-us-east-1a |
| subnet-007f0aeccf5f30758 | 10.0.11.0/24 | us-east-1b | Private | nextera-csa-poc-private-us-east-1b |

---

## 2. VPC

**VPC ID:** vpc-012a60d830a2d3cca
**CIDR Block:** 10.0.0.0/16
**Name:** nextera-csa-poc-vpc
**DNS Hostnames:** Enabled (assumed)
**DNS Resolution:** Enabled (assumed)

---

## 3. RDS Database

**Instance Identifier:** `csa-poc-postgres-dev`
**Instance Class:** db.t3.medium (2 vCPU, 4 GB RAM)
**Engine:** PostgreSQL 16.3
**Storage:** 100 GB
**Multi-AZ:** True
**VPC:** vpc-012a60d830a2d3cca
**Backup Retention:** Unknown (needs verification)

---

## 4. S3 Buckets

**Bucket Name:** `nextera-csa-poc-documents`
**Created:** 2026-03-16 19:55:07
**Purpose:** Store contract documents, AI extraction results, audit trails

---

## 5. IAM Roles

### EKS Cluster Roles
- `csa-poc-eks-cluster-role` (custom)
- `nextera-csa-poc-eks-cluster-role` (custom)
- `eksctl-csa-poc-eks-cluster-ServiceRole-QKWUGLGOVJQZ` (eksctl-generated)

### EKS Node Roles
- `csa-poc-eks-node-role` (custom)
- `nextera-csa-poc-eks-node-role` (custom)
- `eksctl-csa-poc-eks-nodegroup-csa-p-NodeInstanceRole-OdH6yVTKj85X` (eksctl-generated)

### IRSA Roles (IAM Roles for Service Accounts)
- `csa-poc-connector-irsa-role` - For contract ingestion service
- `csa-poc-extraction-irsa-role` - For AI extraction service
- `csa-poc-siren-irsa-role` - For Siren load service
- `csa-poc-ui-irsa-role` - For frontend UI
- `csa-poc-service-role` - General service role

### Other Roles
- `nextera-csa-poc-runner-role` - For GitHub Actions runner
- `eksctl-csa-poc-eks-addon-iamserviceaccount-ku-Role1-K1crPgoTxOzF` (VPC CNI)
- `eksctl-csa-poc-eks-addon-vpc-cni-Role1-TNABQlHo1UI3` (VPC CNI)

---

## 6. Secrets Manager

**Secrets:**
1. `nextera-csa-poc-rds-password` - RDS database password
2. `csa-poc/dev/postgres` - PostgreSQL connection details
3. `csa-poc/dev/phoenix-api-key` - Mock Phoenix API key
4. `csa-poc/dev/siren-api-key` - Mock Siren API key

---

## 7. Cost Estimation (staging-server)

### Monthly Cost Breakdown (Estimated)

**EKS Cluster:**
- EKS Control Plane: $73/month
- 2x t3.medium nodes (on-demand): ~$60/month (2 × $0.0416/hour × 730 hours)

**RDS:**
- db.t3.medium Multi-AZ: ~$140/month
- 100 GB storage (Multi-AZ): ~$23/month

**S3:**
- Storage (minimal usage): ~$2-5/month

**Data Transfer:**
- Minimal (internal VPC traffic): ~$5/month

**NAT Gateway (if used):**
- 2 NAT Gateways (Multi-AZ): ~$64/month

**Total Estimated Cost:** ~$367-370/month

---

## 8. Cost-Optimized Plan for nextera-clone

### Target Monthly Cost: ~$80-90/month (within $100 credit)

**Optimizations:**

### EKS Cluster
- **Control Plane:** $73/month (cannot reduce)
- **Nodes:** 1x t3.small (instead of 2x t3.medium)
  - Cost: ~$15/month (1 × $0.021/hour × 730 hours)
  - OR use t3.micro: ~$7.5/month (if workload allows)

### RDS
- **Instance:** db.t4g.micro (ARM-based, cheaper) - Single-AZ
  - Cost: ~$12/month (instead of $140/month)
- **Storage:** 20 GB (instead of 100 GB) - Single-AZ
  - Cost: ~$2.5/month (instead of $23/month)
- **Disable Multi-AZ** (not needed for POC)
- **Backup Retention:** 1 day (minimum)

### S3
- **Storage:** Minimal usage (~$2-5/month)
- **Enable Lifecycle Policies:** Delete old test data after 30 days

### Networking
- **Use Single NAT Gateway** or **VPC Endpoints** instead of NAT Gateway
  - If using NAT Gateway: $32/month (single AZ)
  - If using VPC Endpoints (S3, SQS, Secrets Manager): ~$7-10/month
- **Single-AZ Deployment:** Reduce subnets to 1 public + 1 private

### Application Deployment
- **Pod Replicas:** 1 replica per service (instead of 2-3)
- **Resource Limits:** Reduce CPU/memory requests and limits
- **Disable Non-Essential Services:** Remove monitoring stack (Prometheus, Grafana) if present

**Estimated nextera-clone Cost:** ~$80-95/month

---

## 9. Migration Strategy

### Phase 1: Core Infrastructure (Day 1)
1. Create VPC with single-AZ subnets (1 public, 1 private in us-east-1a)
2. Deploy EKS cluster (1.31) with OIDC provider
3. Create single t3.small node group (min=1, max=2, desired=1)
4. Set up IAM roles for EKS cluster and node group

### Phase 2: Data Layer (Day 1-2)
1. Create db.t4g.micro RDS PostgreSQL instance (Single-AZ, 20GB)
2. Create S3 bucket with lifecycle policies
3. Create Secrets Manager secrets (copy from staging-server)

### Phase 3: IRSA and Service Accounts (Day 2)
1. Create IRSA IAM roles with trust policies for OIDC
2. Create Kubernetes ServiceAccounts with IAM role annotations
3. Verify IRSA authentication works

### Phase 4: Application Deployment (Day 2-3)
1. Deploy Helm charts with cost-optimized values
2. Set pod replicas to 1 for all services
3. Configure resource limits (reduced CPU/memory)
4. Verify all pods start successfully

### Phase 5: Testing (Day 3)
1. Test end-to-end workflow (contract discovery → extraction → routing)
2. Verify S3 access via IRSA
3. Verify RDS connectivity
4. Verify Secrets Manager access

### Phase 6: Teardown staging-server (Day 4)
1. Backup any critical data from staging-server
2. Delete EKS cluster
3. Delete RDS instance (with final snapshot)
4. Delete S3 bucket (after confirming data in nextera-clone)
5. Delete IAM roles and policies
6. Delete VPC and subnets

---

## 10. Next Steps

1. ✅ Audit staging-server infrastructure (COMPLETED)
2. ⏳ Create Terraform/eksctl scripts for nextera-clone
3. ⏳ Deploy cost-optimized infrastructure to nextera-clone
4. ⏳ Migrate Helm charts and deploy applications
5. ⏳ Test and verify functionality
6. ⏳ Teardown staging-server

---

## Notes

- **OIDC Provider:** Must be enabled in nextera-clone EKS cluster for IRSA to work
- **Kubernetes Version:** Use same version (1.31) for compatibility
- **Helm Charts:** Already exist in `/helm` directory, just need to update values for nextera-clone
- **Docker Images:** Should be stored in ECR in staging-server, need to ensure nextera-clone can access them (or re-push to nextera-clone ECR)
