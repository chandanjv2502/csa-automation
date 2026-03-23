#!/bin/bash

# Deploy Cost-Optimized RDS PostgreSQL Instance to nextera-clone
# Based on staging-server setup but with reduced resources

set -e

PROFILE="nextera-clone"
REGION="us-east-1"
CLUSTER_NAME="csa-clone-eks"

echo "========================================="
echo "Deploying RDS PostgreSQL to nextera-clone"
echo "========================================="

# Get VPC ID from EKS cluster
echo "Step 1: Getting VPC ID from EKS cluster..."
VPC_ID=$(aws eks describe-cluster \
  --profile $PROFILE \
  --region $REGION \
  --name $CLUSTER_NAME \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)

echo "VPC ID: $VPC_ID"

# Get subnets (use public subnets since we disabled NAT Gateway)
echo "Step 2: Getting subnets..."
ALL_SUBNETS=$(aws ec2 describe-subnets \
  --profile $PROFILE \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].SubnetId' \
  --output text)

echo "Subnets: $ALL_SUBNETS"

# Create DB Subnet Group
echo "Step 3: Creating DB Subnet Group..."
aws rds create-db-subnet-group \
  --profile $PROFILE \
  --region $REGION \
  --db-subnet-group-name csa-clone-postgres-subnet-group \
  --db-subnet-group-description "Subnet group for CSA Clone PostgreSQL" \
  --subnet-ids $ALL_SUBNETS \
  --tags Key=Project,Value=csa-automation Key=Environment,Value=clone \
  || echo "DB Subnet Group already exists, continuing..."

# Create Security Group for RDS
echo "Step 4: Creating Security Group for RDS..."
RDS_SG_ID=$(aws ec2 create-security-group \
  --profile $PROFILE \
  --region $REGION \
  --group-name csa-clone-rds-sg \
  --description "Security group for CSA Clone PostgreSQL" \
  --vpc-id $VPC_ID \
  --output text \
  --query 'GroupId' 2>/dev/null || \
  aws ec2 describe-security-groups \
    --profile $PROFILE \
    --region $REGION \
    --filters "Name=group-name,Values=csa-clone-rds-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

echo "RDS Security Group ID: $RDS_SG_ID"

# Get EKS cluster security group
echo "Step 5: Getting EKS cluster security group..."
EKS_SG_ID=$(aws eks describe-cluster \
  --profile $PROFILE \
  --region $REGION \
  --name $CLUSTER_NAME \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
  --output text)

echo "EKS Security Group ID: $EKS_SG_ID"

# Allow PostgreSQL traffic from EKS cluster
echo "Step 6: Allowing PostgreSQL traffic from EKS cluster..."
aws ec2 authorize-security-group-ingress \
  --profile $PROFILE \
  --region $REGION \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 5432 \
  --source-group $EKS_SG_ID \
  2>/dev/null || echo "Ingress rule already exists, continuing..."

# Generate random password for RDS
echo "Step 7: Generating random password for RDS..."
RDS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Store password in Secrets Manager
echo "Step 8: Storing RDS password in Secrets Manager..."
aws secretsmanager create-secret \
  --profile $PROFILE \
  --region $REGION \
  --name nextera-csa-clone-rds-password \
  --description "RDS PostgreSQL password for CSA Clone" \
  --secret-string "$RDS_PASSWORD" \
  --tags Key=Project,Value=csa-automation Key=Environment,Value=clone \
  2>/dev/null || \
  aws secretsmanager update-secret \
    --profile $PROFILE \
    --region $REGION \
    --secret-id nextera-csa-clone-rds-password \
    --secret-string "$RDS_PASSWORD"

echo "RDS password stored in Secrets Manager: nextera-csa-clone-rds-password"

# Create RDS instance - COST-OPTIMIZED
echo "Step 9: Creating RDS PostgreSQL instance (db.t4g.micro, Single-AZ)..."
aws rds create-db-instance \
  --profile $PROFILE \
  --region $REGION \
  --db-instance-identifier csa-clone-postgres \
  --db-instance-class db.t4g.micro \
  --engine postgres \
  --engine-version 16.3 \
  --master-username csaadmin \
  --master-user-password "$RDS_PASSWORD" \
  --allocated-storage 20 \
  --storage-type gp3 \
  --db-subnet-group-name csa-clone-postgres-subnet-group \
  --vpc-security-group-ids $RDS_SG_ID \
  --no-multi-az \
  --backup-retention-period 1 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "mon:04:00-mon:05:00" \
  --no-publicly-accessible \
  --tags Key=Project,Value=csa-automation Key=Environment,Value=clone Key=ManagedBy,Value=script \
  || echo "RDS instance already exists or error occurred"

echo "Step 10: Waiting for RDS instance to be available (this may take 5-10 minutes)..."
aws rds wait db-instance-available \
  --profile $PROFILE \
  --region $REGION \
  --db-instance-identifier csa-clone-postgres

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --profile $PROFILE \
  --region $REGION \
  --db-instance-identifier csa-clone-postgres \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "========================================="
echo "RDS PostgreSQL Deployment Complete!"
echo "========================================="
echo "RDS Instance: csa-clone-postgres"
echo "Endpoint: $RDS_ENDPOINT"
echo "Port: 5432"
echo "Username: csaadmin"
echo "Password: (stored in Secrets Manager: nextera-csa-clone-rds-password)"
echo "Database: postgres (default)"
echo "========================================="

# Store RDS connection details in Secrets Manager
echo "Step 11: Storing RDS connection details in Secrets Manager..."
RDS_SECRET_JSON=$(cat <<EOF
{
  "host": "$RDS_ENDPOINT",
  "port": 5432,
  "username": "csaadmin",
  "password": "$RDS_PASSWORD",
  "database": "postgres",
  "engine": "postgres"
}
EOF
)

aws secretsmanager create-secret \
  --profile $PROFILE \
  --region $REGION \
  --name csa-clone/postgres \
  --description "PostgreSQL connection details for CSA Clone" \
  --secret-string "$RDS_SECRET_JSON" \
  --tags Key=Project,Value=csa-automation Key=Environment,Value=clone \
  2>/dev/null || \
  aws secretsmanager update-secret \
    --profile $PROFILE \
    --region $REGION \
    --secret-id csa-clone/postgres \
    --secret-string "$RDS_SECRET_JSON"

echo "RDS connection details stored in Secrets Manager: csa-clone/postgres"
echo "========================================="
echo "Script completed successfully!"
echo "========================================="
