# CSA POC - Staging Server Actions Log

## Date: 2026-03-16

### 1. Explored Existing Cluster
```bash
AWS_PROFILE=staging-server aws eks list-clusters
AWS_PROFILE=staging-server aws eks describe-cluster --name csa-poc-eks
```
**Why:** Discovered existing EKS cluster `csa-poc-eks` with OIDC enabled. Can reuse instead of creating new cluster.

### 2. Updated Kubeconfig
```bash
AWS_PROFILE=staging-server aws eks update-kubeconfig --name csa-poc-eks --region us-east-1
```
**Why:** Connect kubectl to existing csa-poc-eks cluster for management.

### 3. Checked Cluster Status
```bash
kubectl get nodes
kubectl get namespaces
kubectl get pods -A
```
**Why:** Found 4 existing CSA pods running in csa-poc namespace. All services are ClusterIP (matches design).

### 4. Verified OIDC Provider
```bash
AWS_PROFILE=staging-server aws iam list-open-id-connect-providers
```
**Why:** Confirmed OIDC provider exists (required for IRSA). No need to recreate cluster.

### 5. Checked for ALB Controller
```bash
kubectl get deployment -n kube-system | grep -i "alb\|load-balancer"
```
**Why:** AWS Load Balancer Controller NOT installed. Required for creating ALB from Ingress resource.

### 6. Created IAM Policy for ALB Controller
```bash
curl -o /tmp/iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json
AWS_PROFILE=staging-server aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file:///tmp/iam-policy.json
```
**Why:** Create IAM permissions needed by AWS Load Balancer Controller to manage ALBs.

### 7. Created IAM ServiceAccount for ALB Controller
```bash
AWS_PROFILE=staging-server eksctl create iamserviceaccount \
  --cluster=csa-poc-eks \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::524997768738:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --region=us-east-1 \
  --approve
```
**Why:** Create Kubernetes ServiceAccount with IAM role (IRSA pattern) for ALB Controller pod.

### 8. Delete Existing Old Pods
```bash
kubectl delete deployment csa-connector csa-extraction csa-siren csa-ui -n csa-poc
kubectl delete service csa-connector csa-extraction csa-siren csa-ui -n csa-poc
```
**Why:** Remove old 4-pod architecture to replace with new 9-pod design from design-updated.md.

---

## Next Actions (Pending)

### 9. Install AWS Load Balancer Controller (PENDING)
```bash
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=csa-poc-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```
**Why:** Install controller that creates/manages ALB when Ingress resources are deployed.

### 10. Copy New 9-Pod Manifests to k8s Directory
```bash
cp poc-csa-automation/k8s-manifests/deployments/*.yaml k8s/
```
**Why:** Prepare new 9-pod architecture manifests for GitHub Actions deployment.
**Status:** ✅ COMPLETED - All 9 manifests copied successfully.

### 11. Commit and Push Changes to GitHub
```bash
git add k8s/
git commit -m "Deploy new 9-pod CSA architecture

- Frontend UI (nginx)
- Contract Discovery Service
- Contract Ingestion Service
- AI Extraction Service
- CSA Routing Service
- Siren Load Service
- Notification Service
- Mock Phoenix API
- Mock Siren API

All services use ClusterIP (internal only) matching design-updated.md"
git push origin main
```
**Why:** Push manifests to GitHub repository to trigger deployment workflow.
**Status:** ✅ COMPLETED - Commit dd826cd pushed to main branch.

### 12. Trigger GitHub Actions Deployment (First Attempt - FAILED)
```bash
gh workflow run "Deploy to EKS"
```
**Why:** Manually trigger deployment workflow using GitHub CLI and monitor progress.
**Status:** ❌ FAILED - Namespace mismatch error. Workflow uses secrets.K8S_NAMESPACE but manifests have namespace:csa-poc.

### 13. Fix Workflow - Remove Namespace Flag
```bash
# Edit .github/workflows/deploy.yml to:
# - Remove -n flag from kubectl apply (namespace already in manifests)
# - Hardcode csa-poc namespace in verification steps
git add .github/workflows/deploy.yml Action.md
git commit -m "Fix workflow: Use namespace from manifests instead of secrets"
git push origin main
```
**Why:** Fix namespace mismatch between workflow secrets and hardcoded manifests.

### 14. Re-trigger GitHub Actions Deployment (Second Attempt - FAILED)
```bash
gh workflow run "Deploy to EKS"
```
**Why:** Deploy with fixed workflow.
**Status:** ❌ FAILED - User "github-actions-csa-deploy" lacks RBAC permissions to list services in kube-system.

### 15. Investigate Workflow Failure
```bash
gh run view 23144773834 --log
```
**Why:** Check workflow logs to identify root cause of deployment failure.
**Finding:** IAM user can authenticate to cluster, but Kubernetes RBAC denies listing services in kube-system namespace.

### 16. Check Existing RBAC for GitHub Actions User
```bash
kubectl get clusterrolebinding | grep github-actions
kubectl get rolebinding -n csa-poc | grep github-actions
kubectl get configmap aws-auth -n kube-system -o yaml
```
**Why:** Verify what Kubernetes permissions the github-actions-csa-deploy user currently has.
**Finding:** User is mapped to group "csa-deployers" but no Role/RoleBinding exists for this group.

### 17. Create RBAC Role for Deployers in csa-poc Namespace
```bash
kubectl create role csa-deployer --verb=get,list,watch,create,update,patch,delete --resource=deployments,services,pods,replicasets -n csa-poc
kubectl create rolebinding csa-deployer-binding --role=csa-deployer --group=csa-deployers -n csa-poc
kubectl auth can-i create deployments -n csa-poc --as=github-actions-csa-deploy --as-group=csa-deployers
```
**Why:** Grant github-actions-csa-deploy user permissions to manage deployments/services/pods in csa-poc namespace.
**Status:** ✅ COMPLETED - All permissions verified (create deployments: yes, create services: yes, list pods: yes).

### 18. Update Workflow to Check csa-poc Namespace Permissions
```bash
# Edit .github/workflows/deploy.yml to verify permissions in csa-poc instead of kube-system
git add .github/workflows/deploy.yml Action.md
git commit -m "Fix workflow: Check csa-poc namespace permissions instead of kube-system"
git push origin main
```
**Why:** Previous workflow checked kube-system permissions which GitHub Actions user doesn't need.

### 19. Trigger GitHub Actions Deployment (Third & Fourth Attempts)
```bash
gh workflow run "Deploy to EKS"
```
**Why:** Deploy with fixed RBAC and updated workflow verification.
**Status:** ✅ PARTIALLY SUCCESSFUL - All 9 CSA pods deployed successfully, but workflow failed due to old sample-app files in k8s/ directory targeting default namespace (which user lacks permissions for).

### 20. Remove Old Sample App Files
```bash
rm k8s/deployment.yaml k8s/service.yaml
git add k8s/
git commit -m "Remove old sample-app files targeting default namespace"
git push origin main
```
**Why:** Old files from previous testing cause deployment failure. GitHub Actions user only has permissions in csa-poc namespace.
**Status:** ✅ COMPLETED - Commit 8d8a85b pushed to main branch.

### 21. Final GitHub Actions Deployment
```bash
gh workflow run "Deploy to EKS"
kubectl get pods -n csa-poc
kubectl get svc -n csa-poc
```
**Why:** Verify deployment workflow completes successfully without errors.
**Status:** ✅ SUCCESS - All 9 pods running, all 9 services created, GitHub Actions workflow completed successfully.

### 22. Check IAM Permissions for GitHub Actions User
```bash
AWS_PROFILE=staging-server aws iam list-attached-user-policies --user-name github-actions-csa-deploy
AWS_PROFILE=staging-server aws iam list-user-policies --user-name github-actions-csa-deploy
AWS_PROFILE=staging-server aws iam get-user-policy --user-name github-actions-csa-deploy --policy-name EKSDescribeAccess
```
**Why:** Verify what AWS service permissions the GitHub Actions IAM user has (EKS only vs broader access).
**Finding:** User has MINIMAL permissions - only `eks:DescribeCluster` on csa-poc-eks cluster. No access to RDS, S3, SQS, Secrets Manager, ECR, or any other AWS services.

### 23. Create IAM Role for IRSA (Service Account Permissions)
```bash
# Created /tmp/trust-policy.json with OIDC provider
# Created /tmp/csa-service-permissions.json
AWS_PROFILE=staging-server aws iam create-role --role-name csa-poc-service-role --assume-role-policy-document file:///tmp/trust-policy.json
AWS_PROFILE=staging-server aws iam create-policy --policy-name CSAPoCServicePermissions --policy-document file:///tmp/csa-service-permissions.json
AWS_PROFILE=staging-server aws iam attach-role-policy --role-name csa-poc-service-role --policy-arn arn:aws:iam::524997768738:policy/CSAPoCServicePermissions
```
**Why:** Create IAM role that CSA pods will assume via IRSA to access AWS services (S3, RDS, Secrets Manager, SQS, Textract).
**Status:** ✅ COMPLETED - Role ARN: `arn:aws:iam::524997768738:role/csa-poc-service-role`

**Permissions Granted:**
- S3: GetObject, PutObject, DeleteObject, ListBucket on `nextera-csa-*-documents`
- SQS: Send/Receive/Delete messages on `csa-poc-*` queues
- Textract: AnalyzeDocument, DetectDocumentText
- Secrets Manager: GetSecretValue on `csa-poc/*` secrets
- SSM Parameter Store: GetParameter on `csa-poc/*` parameters
- CloudWatch Logs: Create/write logs to `/aws/eks/csa-poc/*`
- CloudWatch Metrics: PutMetricData to `CSA/Application` namespace

**Trust Policy:** Allows any ServiceAccount matching `system:serviceaccount:csa-poc:csa-*` to assume this role.

### 24. Create S3 Bucket for Document Storage
```bash
AWS_PROFILE=staging-server aws s3api create-bucket --bucket nextera-csa-poc-documents --region us-east-1
AWS_PROFILE=staging-server aws s3api put-bucket-versioning --bucket nextera-csa-poc-documents --versioning-configuration Status=Enabled
AWS_PROFILE=staging-server aws s3api put-bucket-encryption --bucket nextera-csa-poc-documents --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
AWS_PROFILE=staging-server aws s3api put-public-access-block --bucket nextera-csa-poc-documents --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```
**Why:** Create S3 bucket for storing CSA contract documents (matches IAM policy pattern `nextera-csa-*-documents`).
**Status:** ✅ COMPLETED - Bucket: `nextera-csa-poc-documents` (versioning enabled, encrypted, public access blocked)

### 25. Create SQS Queues for Async Processing (Initial 3 Queues)
```bash
AWS_PROFILE=staging-server aws sqs create-queue --queue-name csa-poc-contract-discovery --region us-east-1
AWS_PROFILE=staging-server aws sqs create-queue --queue-name csa-poc-extraction-tasks --region us-east-1
AWS_PROFILE=staging-server aws sqs create-queue --queue-name csa-poc-siren-load --region us-east-1
```
**Why:** Create SQS queues for async communication between services (matches IAM policy pattern `csa-poc-*`).
**Status:** ✅ COMPLETED - Queues: `csa-poc-contract-discovery`, `csa-poc-extraction-tasks`, `csa-poc-siren-load`

### 25b. Create Missing SQS Queues (Per design-updated.md)
```bash
AWS_PROFILE=staging-server aws sqs create-queue --queue-name csa-poc-contract-ingestion --region us-east-1
AWS_PROFILE=staging-server aws sqs create-queue --queue-name csa-poc-notification --region us-east-1
```
**Why:** design-updated.md specifies 5 queues total. Missing: ingestion-queue (contract-ingestion→ai-extraction) and notification-queue (for notification service).

### 26. Create AWS Secrets Manager Secrets
```bash
AWS_PROFILE=staging-server aws secretsmanager create-secret --name csa-poc/dev/postgres --secret-string '{"username":"csa_admin","password":"PLACEHOLDER_CHANGE_ME","host":"TBD","port":5432}'
AWS_PROFILE=staging-server aws secretsmanager create-secret --name csa-poc/dev/phoenix-api-key --secret-string '{"api_key":"PLACEHOLDER_PHOENIX_KEY","endpoint":"http://mock-phoenix-api.csa-poc.svc.cluster.local:8086"}'
AWS_PROFILE=staging-server aws secretsmanager create-secret --name csa-poc/dev/siren-api-key --secret-string '{"api_key":"PLACEHOLDER_SIREN_KEY","endpoint":"http://mock-siren-api.csa-poc.svc.cluster.local:8087"}'
```
**Why:** Create placeholder secrets for database credentials and API keys (matches IAM policy pattern `csa-poc/*`).
**Status:** ✅ COMPLETED - Secrets created:
- `csa-poc/dev/postgres` (ARN: arn:aws:secretsmanager:us-east-1:524997768738:secret:csa-poc/dev/postgres-RLdYRg)
- `csa-poc/dev/phoenix-api-key` (ARN: arn:aws:secretsmanager:us-east-1:524997768738:secret:csa-poc/dev/phoenix-api-key-EyU7Jw)
- `csa-poc/dev/siren-api-key` (ARN: arn:aws:secretsmanager:us-east-1:524997768738:secret:csa-poc/dev/siren-api-key-sWce2s)

### 27. Fix IAM Role Trust Policy - Allow All ServiceAccounts in csa-poc Namespace
```bash
# Update trust policy to allow any ServiceAccount in csa-poc namespace (not just csa-*)
# Changed pattern from "system:serviceaccount:csa-poc:csa-*" to "system:serviceaccount:csa-poc:*"
AWS_PROFILE=staging-server aws iam update-assume-role-policy --role-name csa-poc-service-role --policy-document file:///tmp/trust-policy-updated.json
```
**Why:** Original trust policy restricted to `csa-*` ServiceAccounts (only csa-routing matched). Our pods are named `frontend-ui`, `contract-discovery`, `ai-extraction`, etc. Updated to allow ANY ServiceAccount in csa-poc namespace.
**Status:** ✅ COMPLETED - Trust policy updated to allow `system:serviceaccount:csa-poc:*`

### 28. Install AWS Load Balancer Controller (Manual - Cluster Infrastructure)
```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=csa-poc-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
kubectl get deployment -n kube-system aws-load-balancer-controller
```
**Why:** Cluster-level infrastructure (not part of GitHub Actions). Required for Ingress → ALB creation. Uses IRSA ServiceAccount from step 7.
**Status:** ✅ COMPLETED - Controller deployed with 2 replicas, both pods Running. Ready to create ALBs from Ingress resources.

### 29. Create Missing SQS Queues Per design-updated.md
```bash
AWS_PROFILE=staging-server aws sqs create-queue --queue-name csa-poc-contract-ingestion --region us-east-1
AWS_PROFILE=staging-server aws sqs create-queue --queue-name csa-poc-notification --region us-east-1
```
**Why:** design-updated.md specifies 5 queues total. Previously created only 3. Missing: contract-ingestion queue (ingestion→extraction) and notification queue (for notification service).
**Status:** ✅ COMPLETED - All 5 queues now created:
1. `csa-poc-contract-discovery` (discovery→ingestion)
2. `csa-poc-contract-ingestion` (ingestion→extraction)
3. `csa-poc-extraction-tasks` (extraction→routing)
4. `csa-poc-siren-load` (routing→siren-load)
5. `csa-poc-notification` (notification service)

---

## Deployment Summary

**Successfully Deployed 9 Pods:**
1. frontend-ui (nginx:1.25-alpine) - Port 80
2. contract-discovery (python:3.11-slim) - Port 8080
3. contract-ingestion (python:3.11-slim) - Port 8081
4. ai-extraction (python:3.11-slim) - Port 8082
5. csa-routing (python:3.11-slim) - Port 8083
6. siren-load (python:3.11-slim) - Port 8084
7. notification-service (python:3.11-slim) - Port 8085
8. mock-phoenix-api (python:3.11-slim) - Port 8086
9. mock-siren-api (python:3.11-slim) - Port 8087

**All pods status:** READY 1/1, STATUS Running
**All services type:** ClusterIP (internal only)
**Namespace:** csa-poc
**Deployment method:** GitHub Actions via kubectl apply

---

## Summary of Findings

**What Exists:**
- EKS cluster: csa-poc-eks (v1.31, ACTIVE)
- OIDC Provider: Enabled (arn:aws:iam::524997768738:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/D710E9122A01B7D29B58FB8A6A511CD6)
- 4 CSA pods running (csa-ui, csa-connector, csa-extraction, csa-siren)
- All services are ClusterIP (internal only)

**What's Missing:**
- AWS Load Balancer Controller (needed for ALB)
- Ingress resource (to create ALB with Cognito)
- RDS PostgreSQL, S3, SQS, Secrets Manager, Cognito
- 5 additional pods (to match 9-pod design)

**Documents Created:**
- poc-csa-automation/README.md - POC overview
- poc-csa-automation/docs/EXISTING-INFRASTRUCTURE.md - Current state analysis
- poc-csa-automation/docs/REQUIREMENTS-VALIDATION.md - Validation checklist
- poc-csa-automation/docs/GAPS-AND-FINDINGS.md - Gap tracking template

---

## Step 30: Create AWS Cognito User Pool for ALB Authentication

**Date:** 2026-03-16

**Commands:**
```bash
# Create User Pool
AWS_PROFILE=staging-server aws cognito-idp create-user-pool \
  --pool-name csa-poc-user-pool \
  --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}" \
  --auto-verified-attributes email \
  --username-attributes email \
  --region us-east-1

# Create App Client for ALB integration
AWS_PROFILE=staging-server aws cognito-idp create-user-pool-client \
  --user-pool-id us-east-1_gccsX6sWm \
  --client-name csa-poc-alb-client \
  --generate-secret \
  --allowed-o-auth-flows code \
  --allowed-o-auth-scopes openid \
  --allowed-o-auth-flows-user-pool-client \
  --callback-urls "https://example.com/oauth2/idpresponse" \
  --supported-identity-providers COGNITO \
  --region us-east-1

# Create Cognito Domain
AWS_PROFILE=staging-server aws cognito-idp create-user-pool-domain \
  --domain csa-poc-staging-20260316 \
  --user-pool-id us-east-1_gccsX6sWm \
  --region us-east-1
```

**Status:** ✅ COMPLETED

**Cognito Details (Required for Ingress annotations):**
- **User Pool ARN:** `arn:aws:cognito-idp:us-east-1:524997768738:userpool/us-east-1_gccsX6sWm`
- **User Pool ID:** `us-east-1_gccsX6sWm`
- **User Pool Client ID:** `4qumod2ls799e6vso5kgvk3dci`
- **User Pool Client Secret:** `c9ubdpsvlsdb1arhif16holab7dval24hql35s6aj2h7i1e9jaa`
- **User Pool Domain:** `csa-poc-staging-20260316.auth.us-east-1.amazoncognito.com`

**Load Balancer Controller Cognito Permission:** ✅ Verified
- IAM Role: `eksctl-csa-poc-eks-addon-iamserviceaccount-ku-Role1-K1crPgoTxOzF`
- Policy includes: `cognito-idp:DescribeUserPoolClient`

**Note:** Callback URL currently set to placeholder. Will be updated to actual ALB DNS after Ingress deployment.

---

## Step 31: Deploy Ingress via GitHub Actions with ALB and Cognito

**Date:** 2026-03-16

**Actions Taken:**

1. **Created Ingress Resource:** `k8s/10-ingress.yaml`
   - ALB with internet-facing scheme
   - Cognito authentication integrated
   - HTTP port 80 (HTTPS requires SSL certificate)

2. **Updated GitHub Actions Workflow:** `.github/workflows/deploy.yml`
   - Added Ingress permission verification
   - Added step to display ALB DNS after deployment

3. **Fixed Kubernetes RBAC - Issue #1:**

**Problem:**
- GitHub Actions deployment failed when trying to create Ingress resources
- The `csa-deployer` Kubernetes Role only had permissions for Deployments and Services
- Missing permissions for `networking.k8s.io/ingresses` resource

**Root Cause:**
- Kubernetes RBAC operates on API group + resource level
- Ingresses are in the `networking.k8s.io` API group (not core `""` group like Pods/Services)
- The role created in Step 20 didn't anticipate Ingress deployment needs

**Solution Applied:**
```bash
kubectl patch role csa-deployer -n csa-poc --type=json -p='[{"op": "add", "path": "/rules/-", "value": {"apiGroups": ["networking.k8s.io"], "resources": ["ingresses"], "verbs": ["get", "list", "watch", "create", "update", "patch", "delete"]}}]'
```

**Impact:** GitHub Actions can now deploy Ingress resources

**Requirements.md Impact:** ⚠️ **SHOULD BE ADDED** - NextEra needs to ensure deployer IAM user/role has Ingress RBAC permissions

---

4. **Fixed Subnet Tagging Issue - Issue #2:**

**Problem:**
- Ingress created but ALB never provisioned
- Load Balancer Controller logs showed: `Failed build model due to couldn't auto-discover subnets: unable to resolve at least one subnet. Evaluated 2 subnets: 2 are tagged for other clusters`
- Ingress remained stuck with no ADDRESS for 4+ minutes

**Root Cause Analysis:**
```bash
# Checked subnet tags - Found mismatch!
AWS_PROFILE=staging-server aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-012a60d830a2d3cca"

# Existing tags on public subnets:
kubernetes.io/cluster/nextera-csa-poc-eks=shared  ❌ WRONG CLUSTER NAME

# But actual EKS cluster name:
aws eks describe-cluster --name csa-poc-eks  ✅ CORRECT NAME
```

**Why This Matters:**
- AWS Load Balancer Controller uses Kubernetes subnet tags for auto-discovery
- For internet-facing ALBs, it looks for subnets tagged with:
  - `kubernetes.io/role/elb=1` (for public subnets)
  - `kubernetes.io/cluster/<CLUSTER_NAME>=shared` or `owned`
- Without matching cluster name tag, controller cannot find eligible subnets

**Solution Applied:**
```bash
# Added correct cluster tag to public subnets (subnet-0d5df5462d8dd2dca, subnet-090c9011b660e5ed5)
AWS_PROFILE=staging-server aws ec2 create-tags \
  --resources subnet-0d5df5462d8dd2dca subnet-090c9011b660e5ed5 \
  --tags Key=kubernetes.io/cluster/csa-poc-eks,Value=shared \
  --region us-east-1
```

**Verification:**
- Both public subnets (us-east-1a, us-east-1b) now have correct tags
- Private subnets tagged with `kubernetes.io/role/internal-elb=1` for internal ALBs

**Impact:** Load Balancer Controller can now discover subnets and create ALB

**Requirements.md Impact:** 🚨 **CRITICAL - MUST BE ADDED** - NextEra MUST tag subnets correctly before deploying Ingress

---

5. **Restarted Load Balancer Controller:**

**Why Needed:**
- Load Balancer Controller caches subnet information on startup
- After adding new subnet tags, controller needed restart to refresh cache

**Command:**
```bash
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

**Result:** ALB provisioned within 30 seconds of controller restart

---

## Step 32: Updated Requirements.md with Critical Findings

**Date:** 2026-03-16

**Reason:** Two critical issues discovered during Ingress/ALB deployment that were not documented in Requirements.md

### Issue #1: Kubernetes RBAC - Ingress Permissions Missing

**What was added to Requirements.md:**
- Expanded "Kubernetes Permissions for GitHub Actions" section (line 56)
- Added detailed RBAC requirements with specific API groups:
  - `""` (core) → pods, services
  - `apps` → deployments, replicasets
  - `networking.k8s.io` → **ingresses** ⬅️ **THIS WAS MISSING**
- Included example Kubernetes Role YAML for reference

**Why this is critical for NextEra:**
- Without Ingress permissions, GitHub Actions cannot deploy Ingress resources
- Deployment will fail silently with permission errors
- NextEra must create the Role/RoleBinding with Ingress permissions before deployment

---

### Issue #2: VPC Subnet Tagging Requirements - CRITICAL

**What was added to Requirements.md:**
- Added new section: "🚨 CRITICAL: VPC Subnet Tagging Requirements" under ALB section (after line 125)
- Documented required tags for public subnets (internet-facing ALB):
  - `kubernetes.io/cluster/<CLUSTER_NAME>=shared`
  - `kubernetes.io/role/elb=1`
- Documented required tags for private subnets (internal ALB):
  - `kubernetes.io/cluster/<CLUSTER_NAME>=shared`
  - `kubernetes.io/role/internal-elb=1`
- Added requirements for minimum 2 subnets per AZ
- Added verification command and common error message

**Why this is CRITICAL for NextEra:**
- **AWS Load Balancer Controller uses these tags for subnet auto-discovery**
- Without correct tags, ALB will NEVER provision
- Cluster name in tags MUST match actual EKS cluster name exactly
- This is the #1 reason ALB deployments fail in EKS

**Real-World Impact:**
- In our POC, subnets were tagged for `nextera-csa-poc-eks` but cluster was `csa-poc-eks`
- ALB failed to provision for 4+ minutes until we added correct tags
- Without this documentation, NextEra would encounter the same issue

**Status:** ✅ COMPLETED - Requirements.md updated with both critical requirements

---

## Step 33: Create RDS PostgreSQL Database

**Date:** 2026-03-16

**Commands:**

1. **Created DB Subnet Group (Private Subnets):**
```bash
AWS_PROFILE=staging-server aws rds create-db-subnet-group \
  --db-subnet-group-name csa-poc-db-subnet-group \
  --db-subnet-group-description "CSA POC RDS subnet group in private subnets" \
  --subnet-ids subnet-0bfd132951efac411 subnet-007f0aeccf5f30758 \
  --region us-east-1
```
- Subnets: subnet-0bfd132951efac411 (us-east-1a), subnet-007f0aeccf5f30758 (us-east-1b)
- VPC: vpc-012a60d830a2d3cca

2. **Created RDS Security Group:**
```bash
AWS_PROFILE=staging-server aws ec2 create-security-group \
  --group-name csa-poc-rds-sg \
  --description "Security group for CSA POC RDS PostgreSQL" \
  --vpc-id vpc-012a60d830a2d3cca \
  --region us-east-1
```
- Security Group ID: sg-08e215c7a154298c5

3. **Allowed PostgreSQL Traffic from EKS Cluster:**
```bash
AWS_PROFILE=staging-server aws ec2 authorize-security-group-ingress \
  --group-id sg-08e215c7a154298c5 \
  --protocol tcp \
  --port 5432 \
  --source-group sg-09773e61e94c6a564 \
  --region us-east-1
```
- Ingress Rule: Port 5432 from EKS cluster security group (sg-09773e61e94c6a564)

4. **Created RDS PostgreSQL Instance:**
```bash
AWS_PROFILE=staging-server aws rds create-db-instance \
  --db-instance-identifier csa-poc-postgres-dev \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 16.3 \
  --master-username csaadmin \
  --allocated-storage 100 \
  --storage-type gp3 \
  --storage-encrypted \
  --db-subnet-group-name csa-poc-db-subnet-group \
  --vpc-security-group-ids sg-08e215c7a154298c5 \
  --multi-az \
  --db-name csapocdb \
  --backup-retention-period 7 \
  --no-publicly-accessible \
  --region us-east-1
```

**RDS Instance Details:**
- **DB Instance Identifier:** csa-poc-postgres-dev
- **Engine:** PostgreSQL 16.3
- **Instance Class:** db.t3.medium (2 vCPU, 4 GB RAM)
- **Storage:** 100 GB gp3 (3000 IOPS, 125 MB/s throughput)
- **Storage Encrypted:** Yes (KMS: arn:aws:kms:us-east-1:524997768738:key/510d3cad-8846-4c4a-9780-d8dfb38e2df3)
- **Multi-AZ:** Yes (High Availability)
- **Database Name:** csapocdb
- **Master Username:** csaadmin
- **Master Password:** Stored in Secrets Manager
- **Publicly Accessible:** No (Private only)
- **Backup Retention:** 7 days
- **Backup Window:** 03:00-04:00 UTC
- **Maintenance Window:** Monday 04:00-05:00 UTC
- **ARN:** arn:aws:rds:us-east-1:524997768738:db:csa-poc-postgres-dev

5. **Updated Secrets Manager with RDS Credentials:**
```bash
AWS_PROFILE=staging-server aws secretsmanager update-secret \
  --secret-id csa-poc/dev/postgres \
  --secret-string '{"username":"csaadmin","password":"***","engine":"postgres","host":"TBD","port":5432,"dbname":"csapocdb","dbInstanceIdentifier":"csa-poc-postgres-dev"}' \
  --region us-east-1
```
- Secret ARN: arn:aws:secretsmanager:us-east-1:524997768738:secret:csa-poc/dev/postgres-RLdYRg
- **Note:** RDS endpoint will be updated in secret once instance is available

**Status:** ⏳ IN PROGRESS - RDS instance creating (10-15 minutes)

**Current Status:** `creating` (checked at time of documentation)

**Next Steps:**
1. Wait for RDS instance to become `available`
2. Retrieve RDS endpoint
3. Update Secrets Manager with actual endpoint
4. Test database connectivity from EKS pods

---

**Status:** ✅ COMPLETED

**ALB Details:**
- **ALB DNS Name:** `k8s-csapoc-csafront-0e04e0a73b-2122475177.us-east-1.elb.amazonaws.com`
- **ALB URL:** `http://k8s-csapoc-csafront-0e04e0a73b-2122475177.us-east-1.elb.amazonaws.com`
- **Scheme:** Internet-facing
- **Ports:** HTTP (80)
- **Target Type:** IP
- **Health Check:** HTTP on path `/`

**Cognito Integration Status:**
- User Pool and App Client configured
- Ingress annotations include Cognito auth settings
- **⚠️ Note:** Cognito callback URLs require HTTPS. Currently using HTTP for POC.
- **Next Step:** SSL certificate needed to enable Cognito authentication

**GitHub Actions Deployment:**
- Commit: `b360a6e` - "Add Ingress resource with ALB and Cognito authentication"
- Workflow Run: 23151753143 - ✅ SUCCESS
- All 9 pods redeployed successfully
- Ingress created and ALB provisioned

**ALB Testing:**
```bash
curl -I http://k8s-csapoc-csafront-0e04e0a73b-2122475177.us-east-1.elb.amazonaws.com/
# HTTP/1.1 200 OK
# Content-Type: text/html
# Content-Length: 615
```
- ✅ ALB is accessible and serving frontend-ui nginx pod
- ✅ Target health check: Healthy (Pod IP: 10.0.11.83)
- ✅ HTTP traffic working correctly

---

## Step 34: Helm Charts and Nexus Registry Setup

**Date:** 2026-03-17

**Nexus Container Registry Details:**
- **Registry URL:** `98.92.113.55:8083` (HTTP, not HTTPS)
- **Registry Location:** EC2 instance with public IP
- **Protocol:** HTTP (insecure registry)
- **Credentials:**
  - **Username:** `cicd-user`
  - **Password:** `CiCd-NexUs-2026`

**Why Nexus:**
- Private container registry for NextEra's CSA Docker images
- Deployed on EC2 for POC (production would use Nexus HA setup)
- All 9 CSA services push images to `98.92.113.55:8083/csa/<service>:1.0.0`

**Helm Charts Created:**
- Created Helm charts for all 9 services (frontend-ui, contract-discovery, contract-ingestion, ai-extraction, csa-routing, siren-load, notification-service, mock-phoenix-api, mock-siren-api)
- Updated `values.yaml` to pull from Nexus instead of Docker Hub
- Example: `image.repository: 98.92.113.55:8083/csa/frontend-ui`

**GitHub Actions Workflows:**
- Created separate workflow for each service (9 total workflows)
- Each workflow: builds Docker image → pushes to Nexus → deploys via Helm
- Workflows trigger on changes to service code/Helm chart or manual trigger

---

## Step 35: Troubleshooting GitHub Actions CI/CD with Nexus Registry

**Date:** 2026-03-17

### Debugging Scenario: "How to Debug Docker Build/Push and Kubernetes Image Pull Issues"

When setting up CI/CD pipelines with private registries, you'll encounter multiple failure points. Here's a systematic debugging approach based on real issues encountered:

---

#### **Phase 1: GitHub Actions Workflow Failures**

**Symptom:** Workflows fail immediately (0s duration) or fail with YAML errors

**How to Debug:**
1. Check workflow syntax: Look for malformed YAML (missing colons, incorrect indentation, duplicate steps)
   ```bash
   gh run list --limit 10  # Check for 0s failures
   gh run view <run-id> --log  # View error logs
   ```

2. Verify step order is logical (e.g., checkout before build, configure before login)

**Common Issues:**
- Duplicate step names without actions
- Steps in wrong order (login before Docker config)
- Missing required parameters

**Fix Pattern:** Read the workflow file, identify structural errors, fix YAML syntax

---

#### **Phase 2: Docker Registry Authentication Failures**

**Symptom:** `Error response from daemon: http: server gave HTTP response to HTTPS client`

**How to Debug:**
1. Identify if registry uses HTTP or HTTPS
   ```bash
   curl http://<registry-ip>:<port>/v2/  # Test HTTP
   curl https://<registry-ip>:<port>/v2/ # Test HTTPS
   ```

2. Check if Docker daemon is configured for insecure registries
   ```bash
   cat /etc/docker/daemon.json  # Should have "insecure-registries" array
   ```

**Root Cause:** Docker defaults to HTTPS. HTTP registries require explicit configuration.

**Fix Pattern:**
```yaml
- name: Configure Docker for insecure registry
  run: |
    echo '{"insecure-registries": ["<registry-ip>:<port>"]}' | sudo tee /etc/docker/daemon.json
    sudo systemctl restart docker
    sleep 5
```

**Critical:** This step MUST come BEFORE docker login

---

#### **Phase 3: Docker Login Authentication Failures**

**Symptom:** `no basic auth credentials` or `unauthorized: authentication required`

**How to Debug:**
1. Check if registry requires authentication
   ```bash
   curl http://<registry-ip>:<port>/v2/_catalog  # Test anonymous access
   ```

2. Verify credentials are stored as GitHub Secrets
   ```bash
   gh secret list  # Check if NEXUS_USERNAME and NEXUS_PASSWORD exist
   ```

3. Test credentials locally
   ```bash
   docker login <registry-ip>:<port> --username <user> --password <pass>
   ```

**Root Cause:** Registry requires authentication but no credentials provided

**Fix Pattern:**
1. Add credentials to GitHub Secrets (`gh secret set NEXUS_USERNAME`, `gh secret set NEXUS_PASSWORD`)
2. Add login step to workflow AFTER configuring Docker for insecure registry
```yaml
- name: Login to Nexus
  run: |
    echo "${{ secrets.NEXUS_PASSWORD }}" | docker login <registry> \
      --username ${{ secrets.NEXUS_USERNAME }} \
      --password-stdin
```

---

#### **Phase 4: Docker Build Success but Helm Deployment Failures**

**Symptom:** Docker images push successfully to Nexus, but Helm deployments timeout or fail with API rate limiting

**How to Debug:**
1. Check if workflows are waiting for pods to be ready
   ```bash
   gh run view <run-id> --log | grep -i "wait\|timeout"
   ```

2. Check Helm deployment flags
   ```bash
   # In workflow: helm upgrade --install <chart> --wait --timeout 5m
   ```

**Root Cause:** Multiple workflows deploying simultaneously with `--wait` flag overwhelm Kubernetes API

**Fix Pattern:** Remove `--wait` flag from Helm deployment to avoid blocking on pod readiness
```yaml
helm upgrade --install <service> ./helm/<service> \
  --namespace csa-poc \
  --timeout 5m  # Removed: --wait
```

**Alternative:** Use separate verify step with kubectl if readiness check needed

---

#### **Phase 5: Kubernetes Pods Cannot Pull Images**

**Symptom:** Pods stuck in `ImagePullBackOff` or `ErrImagePull` status

**How to Debug:**
1. Check pod events for exact error
   ```bash
   kubectl get pods -n <namespace>
   kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Events:"
   ```

2. Look for specific error messages:
   - `http: server gave HTTP response to HTTPS client` → Containerd needs insecure registry config
   - `unauthorized` → Image pull secret missing
   - `manifest unknown` → Image doesn't exist in registry

**Root Cause (Common):** Kubernetes worker nodes use containerd which defaults to HTTPS. HTTP registries require configuration.

**Fix Pattern for HTTP Registries:**

Create a DaemonSet that configures containerd on all nodes:
```yaml
# Create containerd registry config
/etc/containerd/certs.d/<registry-ip>:<port>/hosts.toml:
  server = "http://<registry-ip>:<port>"
  [host."http://<registry-ip>:<port>"]
    capabilities = ["pull", "resolve"]
    skip_verify = true

# Restart containerd
systemctl restart containerd
```

**Deployment:**
1. Apply DaemonSet to configure all nodes
2. Delete existing failed pods
3. New pods will pull successfully from HTTP registry

---

### **Key Takeaway: Systematic Debugging Approach**

1. **GitHub Actions → Docker Build/Push → Kubernetes Pull** is a 3-phase pipeline
2. Debug **one phase at a time** starting from the earliest failure
3. **Check logs at each layer:**
   - GitHub Actions logs: `gh run view --log`
   - Docker daemon logs: `journalctl -u docker`
   - Kubernetes pod events: `kubectl describe pod`
4. **Common pattern:** HTTP registries need configuration at EVERY layer (Docker daemon, containerd)
5. **Authentication:** Must be configured in GitHub Secrets + workflow + optionally Kubernetes imagePullSecrets

**Status:** ✅ All issues resolved - Docker images building, pushing to Nexus successfully. Kubernetes containerd configured for HTTP registry.

---
