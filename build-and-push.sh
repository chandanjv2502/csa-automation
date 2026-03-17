#!/bin/bash

# Build and push all CSA services to Nexus registry
# Registry: 10.0.1.184:8083

set -e  # Exit on error

REGISTRY="98.92.113.55:8083"
VERSION="1.0.0"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}CSA Automation - Docker Build & Push${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo "Registry: $REGISTRY"
echo "Version: $VERSION"
echo ""

# Array of services
services=(
    "frontend-ui"
    "contract-discovery"
    "contract-ingestion"
    "ai-extraction"
    "csa-routing"
    "siren-load"
    "notification-service"
    "mock-phoenix-api"
    "mock-siren-api"
)

# Build and push each service
for service in "${services[@]}"; do
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Processing: $service${NC}"
    echo -e "${BLUE}========================================${NC}"

    IMAGE_NAME="$REGISTRY/csa/$service"

    echo -e "${GREEN}[1/3] Building Docker image...${NC}"
    docker build -t "$IMAGE_NAME:$VERSION" -t "$IMAGE_NAME:latest" ./src/$service/

    echo -e "${GREEN}[2/3] Pushing $IMAGE_NAME:$VERSION...${NC}"
    docker push "$IMAGE_NAME:$VERSION"

    echo -e "${GREEN}[3/3] Pushing $IMAGE_NAME:latest...${NC}"
    docker push "$IMAGE_NAME:latest"

    echo -e "${GREEN}✅ $service completed!${NC}"
    echo ""
done

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}All images built and pushed successfully!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo "Images pushed:"
for service in "${services[@]}"; do
    echo "  - $REGISTRY/csa/$service:$VERSION"
    echo "  - $REGISTRY/csa/$service:latest"
done
