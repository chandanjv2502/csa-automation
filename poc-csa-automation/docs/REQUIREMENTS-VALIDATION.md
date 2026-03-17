# Requirements Validation Checklist

## Purpose

This checklist validates that `/Users/chandanjv/Documents/NextEra/Freshsetup/Architechture/Requirements.md` contains ALL necessary information for NextEra to provide infrastructure support for CSA automation deployment.

## Validation Method

After deploying the POC, mark each item below:
- ✅ Confirmed in Requirements.md
- ❌ Missing from Requirements.md
- ⚠️  Partially documented (needs clarification)

---

## 1. GitHub and CI/CD

### GitHub Repository Access
- [ ] Permission to push code explicitly stated
- [ ] Permission to trigger workflow dispatch explicitly stated
- [ ] Confirmation that NextEra provides repo in their GitHub org

### Nexus Container Registry
- [ ] Nexus URL/endpoint requested
- [ ] Authentication method specified (credentials via GitHub secrets)
- [ ] Push permissions confirmed

### EKS Access from GitHub Actions
- [ ] EKS cluster name requested
- [ ] AWS region requested
- [ ] Namespace name requested
- [ ] IAM user for GitHub Actions requested
- [ ] Required permissions documented (kubectl, helm permissions)

### GitHub Actions Runner Environment
- [ ] kubectl installation confirmed
- [ ] aws-cli installation confirmed
- [ ] Helm installation confirmed

### Network Access
- [ ] GitHub Actions → EKS cluster access confirmed
- [ ] GitHub Actions → Nexus registry access confirmed
- [ ] EKS → Nexus registry (for image pull) access confirmed

### Ingress DNS Workflow
- [ ] Process for sharing ALB DNS name documented
- [ ] NextEra DNS team contact/process for CNAME creation documented

---

## 2. AWS Resources

### RDS PostgreSQL
- [ ] Instance identifier naming pattern requested
- [ ] Engine version (15.x or 16.x) specified
- [ ] Instance class (db.t3.medium) specified
- [ ] Storage size (100 GB gp3) specified
- [ ] Multi-AZ requirement specified
- [ ] VPC placement (same as EKS) specified
- [ ] Subnet group (private subnets) specified
- [ ] Security group rules documented (port 5432 from EKS SG)
- [ ] Credentials storage method specified (Secrets Manager)
- [ ] RDS endpoint sharing method documented

### S3 Bucket
- [ ] Bucket naming pattern proposed (nextera-csa-<env>-documents)
- [ ] Region specified (us-east-1)
- [ ] Bucket policy requirements mentioned
- [ ] Access method documented (IRSA via IAM role)

### SQS Queues
- [ ] Number of queues specified (5 queues + 1 DLQ)
- [ ] Queue naming pattern documented
- [ ] Access method documented (IRSA via IAM role)
- [ ] Permissions required listed (SendMessage, ReceiveMessage, DeleteMessage, etc.)

### AWS Secrets Manager
- [ ] Secret naming pattern documented (csa-poc/dev/<secret-name>)
- [ ] List of all secrets required:
  - [ ] PostgreSQL credentials
  - [ ] OpenLink API key (if applicable)
  - [ ] Phoenix API key
  - [ ] Documentum API key (if applicable)
  - [ ] SIREN API key
  - [ ] VectorDB credentials (if applicable)
  - [ ] OCR service API key (if applicable)
- [ ] Access method documented (IRSA via IAM role)

### CloudWatch
- [ ] Log group naming pattern documented
- [ ] Permissions for log creation documented
- [ ] Metrics namespace documented

### SSM Parameter Store
- [ ] Usage documented (non-sensitive config)
- [ ] Naming pattern documented
- [ ] Access permissions documented

---

## 3. Application Load Balancer (ALB)

### ALB Configuration
- [ ] Internet-facing vs internal decision requested
- [ ] AWS Load Balancer Controller installation confirmed
- [ ] SSL certificate ARN requested
- [ ] Domain name confirmed (csa.devrisk.ne.com for dev)

### Cognito Integration
- [ ] Cognito User Pool ARN requested
- [ ] User Pool Client ID requested
- [ ] User Pool Domain requested
- [ ] Callback URLs documented (https://csa.devrisk.ne.com/oauth2/idpresponse)
- [ ] Load Balancer Controller Cognito permissions confirmed

### Example Ingress YAML
- [ ] Request for reference Ingress YAML from existing app
- [ ] IngressClassName to use requested
- [ ] Required annotations pattern requested
- [ ] Health check configuration pattern requested
- [ ] Tags/labels for compliance requested

---

## 4. IAM Roles for Service Accounts (IRSA)

### EKS OIDC Provider
- [ ] OIDC provider ID requested (needed for trust policy)
- [ ] Confirmation that OIDC is enabled on cluster

### IAM Role Creation
- [ ] Trust policy template provided
- [ ] Permission policy template provided
- [ ] Placeholders clearly marked (<AWS_ACCOUNT_ID>, <OIDC_PROVIDER_ID>)
- [ ] Request for role ARN to be shared with Dsider documented

### ServiceAccount Annotation
- [ ] Explanation that Dsider will annotate ServiceAccounts with role ARN
- [ ] Usage in Helm charts documented

### Required Permissions
- [ ] S3 permissions documented (GetObject, PutObject, DeleteObject, ListBucket)
- [ ] SQS permissions documented (SendMessage, ReceiveMessage, DeleteMessage, etc.)
- [ ] Textract permissions documented (AnalyzeDocument, DetectDocumentText)
- [ ] Secrets Manager permissions documented (GetSecretValue)
- [ ] SSM Parameter Store permissions documented
- [ ] CloudWatch Logs permissions documented
- [ ] CloudWatch Metrics permissions documented

---

## 5. Kubernetes Access for Developers

### Developer RBAC
- [ ] IAM user creation for Dsider developers requested
- [ ] Kubernetes RBAC permissions specified (view, describe, exec into pods)
- [ ] Namespace restriction specified (dev environment only)
- [ ] Resource types accessible documented (pods, deployments, services, logs)

---

## 6. Network and Security

### VPC Configuration
- [ ] Confirmation that EKS cluster exists in VPC
- [ ] Private subnet usage for pods confirmed
- [ ] NAT gateway for internet access (for pulling images, calling external APIs)

### Security Groups
- [ ] RDS security group rules documented (port 5432 from EKS node SG)
- [ ] EKS node security group allows outbound to RDS
- [ ] EKS node security group allows outbound to S3 (via VPC endpoint or internet)

### VPC Endpoints (Optional but recommended)
- [ ] S3 VPC endpoint mentioned (optional)
- [ ] SQS VPC endpoint mentioned (optional)
- [ ] Secrets Manager VPC endpoint mentioned (optional)

---

## 7. Environment-Specific Details

### Development Environment
- [ ] Namespace: csa-dev-ns (or confirmed name)
- [ ] Domain: csa.devrisk.ne.com (or confirmed domain)
- [ ] RDS instance identifier pattern
- [ ] S3 bucket name: nextera-csa-dev-documents
- [ ] SQS queue prefix: csa-dev-*
- [ ] Secrets path: csa-poc/dev/*

### UAT Environment (if applicable)
- [ ] Namespace requested
- [ ] Domain requested (csa.uatrisk.ne.com?)
- [ ] Resource naming patterns consistent

### Production Environment (if applicable)
- [ ] Namespace requested
- [ ] Domain requested
- [ ] Resource naming patterns consistent

---

## 8. Missing or Unclear Items (Document Gaps)

### Items POC Revealed as Missing

**Example format:**
```
❌ MISSING: Textract usage limits or throttling configuration
   - Impact: AI extraction service may fail under load
   - Recommendation: Add to Requirements.md under "AWS Services" section

❌ MISSING: DLQ (Dead Letter Queue) configuration for SQS
   - Impact: Failed messages may be lost
   - Recommendation: Add DLQ naming and permissions to Requirements.md

⚠️  UNCLEAR: How to handle multi-environment secrets in Secrets Manager
   - Current: "csa-poc/dev/<secret-name>" documented
   - Question: Is "csa-poc/uat/<secret-name>" the pattern for UAT?
   - Recommendation: Clarify naming pattern for all environments
```

---

## 9. Validation Results

After POC deployment, document:

### Total Items Checked
- Total items in checklist: ___
- Items confirmed in Requirements.md: ___
- Items missing: ___
- Items needing clarification: ___

### Completeness Score
- Score: ___ / ___ (__ %)

### Recommendation
- [ ] Requirements.md is complete and ready to send to NextEra
- [ ] Requirements.md needs updates before sending (see Section 8 above)

---

## 10. POC Deployment Evidence

Document proof that POC validated requirements:

### Infrastructure Created
```bash
# List resources created during POC
aws eks describe-cluster --name csa-poc-cluster
aws rds describe-db-instances --db-instance-identifier csa-poc-postgres-dev
aws s3 ls | grep nextera-csa
aws sqs list-queues | grep csa-dev
```

### Deployment Success
```bash
# List running pods
kubectl get pods -n csa-dev-ns

# Get Ingress and ALB DNS
kubectl get ingress csa-frontend-ingress -n csa-dev-ns
```

### End-to-End Test Results
```
✅ Contract discovery triggered successfully
✅ PDF ingestion completed
✅ AI extraction succeeded with confidence scores
✅ Routing logic executed correctly
✅ Siren load API call succeeded
✅ Notifications sent via email/WebSocket
```

---

## Next Steps After Validation

1. **If Requirements.md is complete:**
   - Mark as validated
   - Send to NextEra (Jeff) with confidence
   - Use POC as reference architecture

2. **If gaps found:**
   - Update Requirements.md with missing items
   - Re-validate changes
   - Send updated version to NextEra

3. **Document lessons learned:**
   - What worked well in POC
   - What challenges encountered
   - Recommendations for NextEra deployment
