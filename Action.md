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

### 25. Create SQS Queues for Async Processing
```bash
AWS_PROFILE=staging-server aws sqs create-queue --queue-name csa-poc-contract-discovery --region us-east-1
AWS_PROFILE=staging-server aws sqs create-queue --queue-name csa-poc-extraction-tasks --region us-east-1
AWS_PROFILE=staging-server aws sqs create-queue --queue-name csa-poc-siren-load --region us-east-1
```
**Why:** Create SQS queues for async communication between services (matches IAM policy pattern `csa-poc-*`).
**Status:** ✅ COMPLETED - Queues: `csa-poc-contract-discovery`, `csa-poc-extraction-tasks`, `csa-poc-siren-load`

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
