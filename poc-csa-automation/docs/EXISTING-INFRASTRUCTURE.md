# Existing Staging Infrastructure Analysis

## Summary

We have an existing EKS cluster `csa-poc-eks` in the `staging-server` AWS account that can be reused for POC validation. This document analyzes what exists and what needs to be added.

---

## ✅ What Already EXISTS

### 1. EKS Cluster
```
Cluster Name: csa-poc-eks
Version: 1.31
Status: ACTIVE
Region: us-east-1
AWS Account: 524997768738
Endpoint: https://D710E9122A01B7D29B58FB8A6A511CD6.gr7.us-east-1.eks.amazonaws.com
```

### 2. OIDC Provider (Required for IRSA)
```
ARN: arn:aws:iam::524997768738:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/D710E9122A01B7D29B58FB8A6A511CD6
OIDC ID: D710E9122A01B7D29B58FB8A6A511CD6
```
✅ **This is critical! IRSA can be configured without recreating the cluster.**

### 3. Networking
```
VPC ID: vpc-012a60d830a2d3cca
Subnets:
  - subnet-0d5df5462d8dd2dca
  - subnet-090c9011b660e5ed5
  - subnet-007f0aeccf5f30758
  - subnet-0bfd132951efac411

Security Group: sg-0ddb1c708e25897d1
```

### 4. Worker Nodes
```
Node 1: ip-10-0-10-218.ec2.internal (private subnet 10.0.10.x)
Node 2: ip-10-0-11-35.ec2.internal (private subnet 10.0.11.x)
Status: Ready
Kubernetes Version: v1.31.14-eks-f69f56f
Age: 6 days 17 hours
```

### 5. Existing Namespaces
```
- csa-poc      (Active, 6d17h)  ← Already has 4 CSA pods
- csa-dev-ns   (Active, 3d6h)   ← Has 2 sample-app pods
- default
- kube-system
- kube-node-lease
- kube-public
```

### 6. Existing CSA Pods (in csa-poc namespace)
```
NAME                              READY   STATUS    RESTARTS   AGE
csa-connector-77d8cc9f74-6lssz    1/1     Running   0          6d9h
csa-extraction-85cf4fbf79-k8qcv   1/1     Running   0          6d9h
csa-siren-594d7576c5-xhc84        1/1     Running   0          6d9h
csa-ui-5dffc6995b-b7hcz           1/1     Running   0          6d9h
```

### 7. Existing Services (in csa-poc namespace)
```
NAME             TYPE        CLUSTER-IP       PORT(S)
csa-connector    ClusterIP   172.20.126.64    8000/TCP
csa-extraction   ClusterIP   172.20.124.49    8001/TCP
csa-siren        ClusterIP   172.20.244.125   8002/TCP
csa-ui           ClusterIP   172.20.191.164   8080/TCP
```
**All services are ClusterIP (internal only) - ✅ Matches design!**

### 8. Container Registry
```
Registry: 10.0.1.184:8083 (Local Nexus)
Image Pattern: 10.0.1.184:8083/csa/<service>:latest
```

---

## ❌ What's MISSING (Needs to be Added)

### 1. AWS Load Balancer Controller
**Status:** NOT INSTALLED
**Required:** Yes (to create ALB from Ingress resource)
**Action:** Install via Helm
```bash
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=csa-poc-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 2. Ingress Resource
**Status:** No ingress resources found
**Required:** Yes (to create ALB with Cognito auth)
**Action:** Create Ingress YAML with ALB annotations

### 3. RDS PostgreSQL
**Status:** No RDS instances found
**Required:** Yes (database for contracts, audit logs)
**Action:** Create via AWS CLI or Terraform

### 4. S3 Bucket
**Status:** No S3 buckets with 'csa' prefix found
**Required:** Yes (store contract PDFs)
**Action:** Create bucket `nextera-csa-dev-documents`

### 5. SQS Queues
**Status:** No SQS queues found
**Required:** Yes (async messaging between services)
**Action:** Create 5 queues + 1 DLQ:
- csa-dev-discovery
- csa-dev-ingestion
- csa-dev-extraction
- csa-dev-routing
- csa-dev-notification
- csa-dev-dlq

### 6. AWS Secrets Manager
**Status:** Not checked (need to verify)
**Required:** Yes (store DB password, API keys)
**Action:** Create secrets with path `csa-poc/dev/*`

### 7. AWS Cognito User Pool
**Status:** Not checked
**Required:** Yes (authentication for ALB)
**Action:** Create Cognito User Pool and App Client

### 8. IAM Roles for IRSA
**Status:** Not checked
**Required:** Yes (pods need AWS service access)
**Action:** Create IAM roles with trust policy for OIDC provider

### 9. Additional Pods (to match design-updated.md)
**Current:** 4 pods (csa-ui, csa-connector, csa-extraction, csa-siren)
**Design:** 9 pods total

**Missing pods:**
- contract-discovery
- contract-ingestion
- csa-routing (exists as csa-siren?)
- siren-load
- notification-service
- mock-phoenix-api
- mock-siren-api

---

## Recommended Approach

### Option 1: Incremental Addition (Recommended)
**Pros:**
- Reuse existing cluster and pods
- Add only what's missing for POC validation
- Faster deployment

**Steps:**
1. Install AWS Load Balancer Controller
2. Create AWS resources (RDS, S3, SQS, Secrets, Cognito)
3. Create IAM roles for IRSA
4. Add missing pods (5 more services)
5. Create Ingress resource with Cognito auth
6. Test end-to-end flow
7. Validate Requirements.md

### Option 2: Fresh Namespace
**Pros:**
- Clean slate for POC
- Doesn't interfere with existing csa-poc namespace
- Can compare old vs new deployment

**Steps:**
1. Create new namespace (e.g., `csa-poc-v2`)
2. Install AWS Load Balancer Controller (shared, one-time)
3. Create AWS resources
4. Deploy all 9 pods in new namespace
5. Create Ingress with Cognito
6. Test and validate

### Option 3: Use csa-dev-ns Namespace
**Pros:**
- Already exists
- Only has sample apps (easy to replace)

**Steps:**
1. Delete sample-app deployments in csa-dev-ns
2. Install AWS Load Balancer Controller
3. Create AWS resources
4. Deploy all 9 CSA pods to csa-dev-ns
5. Create Ingress with Cognito
6. Test and validate

---

## Recommended: Option 1 (Incremental)

Use the existing `csa-poc` namespace and add:
1. AWS Load Balancer Controller (cluster-level, one-time)
2. AWS services (RDS, S3, SQS, Secrets, Cognito)
3. Missing 5 pods
4. Ingress resource

This allows us to:
- Reuse existing infrastructure
- Validate Requirements.md quickly
- Document what NextEra needs to provide

---

## Next Steps

1. ✅ Document existing infrastructure (this file)
2. Install AWS Load Balancer Controller
3. Create AWS resources script
4. Add missing pods (Dockerfiles + Helm charts)
5. Create Ingress with ALB + Cognito
6. Test end-to-end flow
7. Complete REQUIREMENTS-VALIDATION.md checklist
8. Document gaps in GAPS-AND-FINDINGS.md

---

## Cluster Access Details

**Kubeconfig updated:**
```bash
aws eks update-kubeconfig --name csa-poc-eks --region us-east-1 --profile staging-server
```

**Current context:**
```
arn:aws:eks:us-east-1:524997768738:cluster/csa-poc-eks
```

**Verify access:**
```bash
kubectl get nodes
kubectl get pods -n csa-poc
```
