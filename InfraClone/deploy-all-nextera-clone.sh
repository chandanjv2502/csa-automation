#!/bin/bash

# Master Deployment Script for nextera-clone Infrastructure
# Orchestrates deployment of EKS, RDS, S3, and Secrets Manager

set -e

PROFILE="nextera-clone"
REGION="us-east-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "CSA Automation Infrastructure Deployment"
echo "Target: nextera-clone AWS Account"
echo "Region: $REGION"
echo "========================================="
echo ""

# Verify AWS profile exists
echo "Verifying AWS profile '$PROFILE'..."
if ! aws configure list --profile $PROFILE &> /dev/null; then
  echo "ERROR: AWS profile '$PROFILE' not found!"
  echo "Please configure the profile first:"
  echo "  aws configure --profile $PROFILE"
  exit 1
fi

echo "✓ AWS profile verified"
echo ""

# Verify eksctl is installed
echo "Verifying eksctl is installed..."
if ! command -v eksctl &> /dev/null; then
  echo "ERROR: eksctl not found!"
  echo "Please install eksctl: https://eksctl.io/installation/"
  exit 1
fi

echo "✓ eksctl found: $(eksctl version)"
echo ""

# Verify kubectl is installed
echo "Verifying kubectl is installed..."
if ! command -v kubectl &> /dev/null; then
  echo "ERROR: kubectl not found!"
  echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
  exit 1
fi

echo "✓ kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo ""

# Step 1: Deploy EKS Cluster
echo "========================================="
echo "STEP 1: Deploying EKS Cluster"
echo "========================================="
echo "This will take approximately 15-20 minutes..."
echo ""

if aws eks describe-cluster --profile $PROFILE --region $REGION --name csa-clone-eks &> /dev/null; then
  echo "⚠ EKS cluster 'csa-clone-eks' already exists. Skipping creation..."
else
  echo "Creating EKS cluster using eksctl..."
  eksctl create cluster \
    --profile=$PROFILE \
    --config-file="$SCRIPT_DIR/eksctl-config-nextera-clone.yaml"

  echo "✓ EKS cluster created successfully!"
fi

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig \
  --profile $PROFILE \
  --region $REGION \
  --name csa-clone-eks

echo "✓ kubeconfig updated"
echo ""

# Verify cluster access
echo "Verifying cluster access..."
kubectl cluster-info
kubectl get nodes

echo ""
echo "✓ EKS cluster is ready!"
echo ""

# Step 2: Deploy S3 and Secrets Manager
echo "========================================="
echo "STEP 2: Deploying S3 Bucket and Secrets"
echo "========================================="
echo ""

bash "$SCRIPT_DIR/deploy-s3-secrets-nextera-clone.sh"

echo ""
echo "✓ S3 and Secrets deployed successfully!"
echo ""

# Step 3: Deploy RDS PostgreSQL
echo "========================================="
echo "STEP 3: Deploying RDS PostgreSQL"
echo "========================================="
echo "This will take approximately 5-10 minutes..."
echo ""

bash "$SCRIPT_DIR/deploy-rds-nextera-clone.sh"

echo ""
echo "✓ RDS deployed successfully!"
echo ""

# Step 4: Create IRSA IAM Roles
echo "========================================="
echo "STEP 4: Creating IRSA IAM Roles"
echo "========================================="
echo ""

# Get OIDC provider URL
OIDC_PROVIDER=$(aws eks describe-cluster \
  --profile $PROFILE \
  --region $REGION \
  --name csa-clone-eks \
  --query 'cluster.identity.oidc.issuer' \
  --output text | sed 's|https://||')

echo "OIDC Provider: $OIDC_PROVIDER"

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# Create trust policy template
cat > /tmp/irsa-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:SERVICE_NAMESPACE:SERVICE_ACCOUNT_NAME",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

echo "✓ IRSA trust policy template created"
echo ""

# Note: Actual IRSA roles will be created when deploying Helm charts
echo "Note: Individual IRSA roles will be created during Helm chart deployment"
echo ""

# Summary
echo "========================================="
echo "DEPLOYMENT COMPLETE!"
echo "========================================="
echo ""
echo "Resources Created:"
echo "  ✓ EKS Cluster: csa-clone-eks (Kubernetes 1.31)"
echo "  ✓ Node Group: csa-clone-private-nodes (1x t3.small)"
echo "  ✓ RDS Instance: csa-clone-postgres (db.t4g.micro, PostgreSQL 16.3)"
echo "  ✓ S3 Bucket: nextera-csa-clone-documents"
echo "  ✓ Secrets Manager: 4 secrets created"
echo ""
echo "Next Steps:"
echo "  1. Review the deployed resources"
echo "  2. Update Helm chart values for nextera-clone"
echo "  3. Deploy application pods using Helm"
echo "  4. Test end-to-end functionality"
echo "  5. Tear down staging-server infrastructure"
echo ""
echo "Cost Estimate: ~$85-95/month (within $100 credit limit)"
echo ""
echo "========================================="

# Cleanup temp files
rm -f /tmp/irsa-trust-policy.json
