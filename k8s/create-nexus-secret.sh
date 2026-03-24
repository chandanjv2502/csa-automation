#!/bin/bash

# Create Kubernetes ImagePullSecret for Nexus Registry
# This script creates a secret that allows Kubernetes to authenticate with Nexus

set -e

NAMESPACE="csa-clone"
SECRET_NAME="nexus-registry-secret"
NEXUS_SERVER="44.202.63.187:8083"
NEXUS_USERNAME="cicd-user"
NEXUS_PASSWORD="CiCd-NexUs-2026"

echo "========================================="
echo "Creating ImagePullSecret for Nexus"
echo "========================================="

# Create namespace if it doesn't exist
echo "Step 1: Ensuring namespace exists..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Delete existing secret if it exists
echo "Step 2: Removing old secret if exists..."
kubectl delete secret $SECRET_NAME -n $NAMESPACE 2>/dev/null || true

# Create Docker registry secret
echo "Step 3: Creating Docker registry secret..."
kubectl create secret docker-registry $SECRET_NAME \
  --docker-server=$NEXUS_SERVER \
  --docker-username=$NEXUS_USERNAME \
  --docker-password=$NEXUS_PASSWORD \
  --namespace=$NAMESPACE

# Verify secret creation
echo "Step 4: Verifying secret..."
kubectl get secret $SECRET_NAME -n $NAMESPACE

echo ""
echo "========================================="
echo "ImagePullSecret Created Successfully!"
echo "========================================="
echo "Secret Name: $SECRET_NAME"
echo "Namespace: $NAMESPACE"
echo "Registry: $NEXUS_SERVER"
echo ""
echo "This secret will be referenced in all Helm charts to pull images."
echo "========================================="
