# CSA Automation - EKS Deployment

This repository demonstrates automated deployment to Amazon EKS using GitHub Actions.

## Infrastructure

- **EKS Cluster:** csa-poc-eks
- **Region:** us-east-1
- **Namespace:** csa-dev-ns
- **IAM User:** github-actions-csa-deploy

## Architecture

```
GitHub Actions (CI/CD)
         ↓
    (AWS IAM User)
         ↓
   aws-auth ConfigMap
         ↓
  Kubernetes Group: csa-deployers
         ↓
  Kubernetes Role: csa-deployer
         ↓
   Deploy to namespace: csa-dev-ns
```

## GitHub Actions Workflow

The workflow is triggered on:
- Push to `main` branch
- Manual trigger from GitHub UI (workflow_dispatch)

### Workflow Steps:
1. Checkout code
2. Configure AWS credentials
3. Update kubeconfig for EKS cluster
4. Verify authentication and permissions
5. Deploy Kubernetes manifests from `k8s/` directory
6. Verify deployment status

## Kubernetes Resources

### Deployment
- **Name:** sample-app
- **Image:** nginx:1.25-alpine
- **Replicas:** 2
- **Resources:** 100m CPU / 64Mi RAM (request), 200m CPU / 128Mi RAM (limit)
- **Health Checks:** Liveness and readiness probes on port 80

### Service
- **Name:** sample-app-service
- **Type:** ClusterIP
- **Port:** 80

## Secrets Required

The following GitHub secrets must be configured:
- `AWS_ACCESS_KEY_ID` - IAM user access key
- `AWS_SECRET_ACCESS_KEY` - IAM user secret key
- `AWS_REGION` - AWS region (us-east-1)
- `EKS_CLUSTER_NAME` - EKS cluster name (csa-poc-eks)
- `K8S_NAMESPACE` - Target namespace (csa-dev-ns)

## RBAC Permissions

The IAM user is mapped to Kubernetes group `csa-deployers` which has the following permissions in `csa-dev-ns` namespace:
- Full CRUD on: pods, services, deployments, configmaps, secrets, jobs, cronjobs, ingresses
- Read-only on other namespaces: **No access**
- Cluster-level resources: **No access**

## Manual Deployment

To deploy manually:
```bash
# Configure AWS credentials
export AWS_ACCESS_KEY_ID=<your-access-key>
export AWS_SECRET_ACCESS_KEY=<your-secret-key>

# Update kubeconfig
aws eks update-kubeconfig --name csa-poc-eks --region us-east-1

# Deploy
kubectl apply -f k8s/ -n csa-dev-ns

# Verify
kubectl get pods -n csa-dev-ns
kubectl get services -n csa-dev-ns
```

## Security Notes

- All credentials are stored as GitHub secrets (encrypted)
- IAM user has minimal permissions (only eks:DescribeCluster)
- Kubernetes RBAC restricts access to csa-dev-ns namespace only
- No access to cluster-level resources or other namespaces
