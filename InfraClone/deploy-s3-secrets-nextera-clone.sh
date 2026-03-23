#!/bin/bash

# Deploy S3 Buckets and Secrets to nextera-clone
# Cost-optimized with lifecycle policies

set -e

PROFILE="nextera-clone"
REGION="us-east-1"

echo "========================================="
echo "Deploying S3 and Secrets to nextera-clone"
echo "========================================="

# Create S3 bucket for documents
echo "Step 1: Creating S3 bucket for CSA documents..."
BUCKET_NAME="nextera-csa-clone-documents"

aws s3 mb s3://$BUCKET_NAME \
  --profile $PROFILE \
  --region $REGION \
  || echo "Bucket already exists, continuing..."

# Enable versioning (optional, can disable to save costs)
echo "Step 2: Configuring S3 bucket settings..."
aws s3api put-bucket-versioning \
  --profile $PROFILE \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Suspended

# Apply lifecycle policy to delete old test data (cost savings)
echo "Step 3: Applying lifecycle policy (delete objects after 90 days)..."
cat > /tmp/lifecycle-policy.json <<EOF
{
  "Rules": [
    {
      "ID": "DeleteOldTestData",
      "Status": "Enabled",
      "Filter": {},
      "Expiration": {
        "Days": 90
      },
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 30
      }
    }
  ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
  --profile $PROFILE \
  --bucket $BUCKET_NAME \
  --lifecycle-configuration file:///tmp/lifecycle-policy.json

# Apply bucket tags
echo "Step 4: Tagging S3 bucket..."
aws s3api put-bucket-tagging \
  --profile $PROFILE \
  --bucket $BUCKET_NAME \
  --tagging 'TagSet=[{Key=Project,Value=csa-automation},{Key=Environment,Value=clone},{Key=ManagedBy,Value=script}]'

# Enable encryption
echo "Step 5: Enabling S3 bucket encryption..."
aws s3api put-bucket-encryption \
  --profile $PROFILE \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

# Block public access
echo "Step 6: Blocking public access..."
aws s3api put-public-access-block \
  --profile $PROFILE \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "========================================="
echo "S3 bucket created: $BUCKET_NAME"
echo "========================================="

# Create Secrets Manager secrets
echo "Step 7: Creating Secrets Manager secrets..."

# Phoenix API Key (mock)
echo "Creating secret: csa-clone/phoenix-api-key..."
aws secretsmanager create-secret \
  --profile $PROFILE \
  --region $REGION \
  --name csa-clone/phoenix-api-key \
  --description "Mock Phoenix API key for CSA Clone" \
  --secret-string "mock-phoenix-api-key-$(openssl rand -hex 16)" \
  --tags Key=Project,Value=csa-automation Key=Environment,Value=clone \
  2>/dev/null || echo "Secret already exists, skipping..."

# Siren API Key (mock)
echo "Creating secret: csa-clone/siren-api-key..."
aws secretsmanager create-secret \
  --profile $PROFILE \
  --region $REGION \
  --name csa-clone/siren-api-key \
  --description "Mock Siren API key for CSA Clone" \
  --secret-string "mock-siren-api-key-$(openssl rand -hex 16)" \
  --tags Key=Project,Value=csa-automation Key=Environment,Value=clone \
  2>/dev/null || echo "Secret already exists, skipping..."

echo "========================================="
echo "Secrets created successfully!"
echo "========================================="
echo "S3 Bucket: $BUCKET_NAME"
echo "Secrets:"
echo "  - csa-clone/postgres (created by deploy-rds script)"
echo "  - csa-clone/phoenix-api-key"
echo "  - csa-clone/siren-api-key"
echo "  - nextera-csa-clone-rds-password (created by deploy-rds script)"
echo "========================================="
echo "Script completed successfully!"
echo "========================================="

rm /tmp/lifecycle-policy.json
