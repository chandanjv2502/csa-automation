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

### 14. Re-trigger GitHub Actions Deployment
```bash
gh workflow run "Deploy to EKS"
```
**Why:** Deploy with fixed workflow.

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
