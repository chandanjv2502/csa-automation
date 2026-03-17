#!/bin/bash

# Update Helm values to use Nexus registry
NEXUS_REGISTRY="10.0.1.184:8083"

# Update frontend-ui (uses nginx, port 80)
sed -i.bak 's|repository: nginx|repository: '"$NEXUS_REGISTRY"'/csa/frontend-ui|g' helm/frontend-ui/values.yaml
sed -i.bak 's|tag: "1.25-alpine"|tag: "1.0.0"|g' helm/frontend-ui/values.yaml
sed -i.bak 's|containerPort: 8080|containerPort: 80|g' helm/frontend-ui/values.yaml
sed -i.bak 's|targetPort: 8080|targetPort: 80|g' helm/frontend-ui/values.yaml
sed -i.bak 's|port: 8080|port: 80|g' helm/frontend-ui/values.yaml

# Update backend services (use FastAPI, port 8080)
for service in contract-discovery contract-ingestion ai-extraction csa-routing siren-load notification-service mock-phoenix-api mock-siren-api; do
  echo "Updating $service..."
  sed -i.bak 's|repository: python|repository: '"$NEXUS_REGISTRY"'/csa/'"$service"'|g' helm/$service/values.yaml
  sed -i.bak 's|tag: "3.11-slim"|tag: "1.0.0"|g' helm/$service/values.yaml
done

echo "✅ All Helm values updated to use Nexus registry"
