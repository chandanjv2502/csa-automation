#!/bin/bash

# Setup Docker Repositories in Nexus via API
# This script creates docker-hosted, docker-proxy, and docker-group repositories

set -e

NEXUS_HOST="44.202.63.187"
NEXUS_PORT="8081"
NEXUS_USER="admin"
NEXUS_PASS="CstgQa-123"
NEXUS_URL="http://${NEXUS_HOST}:${NEXUS_PORT}"

echo "========================================="
echo "Setting up Docker Repositories in Nexus"
echo "========================================="
echo "Nexus URL: $NEXUS_URL"
echo ""

# Function to create Docker hosted repository
create_docker_hosted() {
    echo "Step 1: Creating docker-hosted repository (port 8083)..."

    curl -X POST "${NEXUS_URL}/service/rest/v1/repositories/docker/hosted" \
        -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "docker-hosted",
            "online": true,
            "storage": {
                "blobStoreName": "default",
                "strictContentTypeValidation": true,
                "writePolicy": "ALLOW"
            },
            "cleanup": null,
            "docker": {
                "v1Enabled": false,
                "forceBasicAuth": true,
                "httpPort": 8083
            }
        }' && echo " ✅ docker-hosted created successfully" || echo " ⚠️  docker-hosted may already exist"

    echo ""
}

# Function to create Docker proxy repository
create_docker_proxy() {
    echo "Step 2: Creating docker-proxy repository (port 8082)..."

    curl -X POST "${NEXUS_URL}/service/rest/v1/repositories/docker/proxy" \
        -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "docker-proxy",
            "online": true,
            "storage": {
                "blobStoreName": "default",
                "strictContentTypeValidation": true
            },
            "cleanup": null,
            "proxy": {
                "remoteUrl": "https://registry-1.docker.io",
                "contentMaxAge": 1440,
                "metadataMaxAge": 1440
            },
            "negativeCache": {
                "enabled": true,
                "timeToLive": 1440
            },
            "httpClient": {
                "blocked": false,
                "autoBlock": true,
                "connection": {
                    "retries": 0,
                    "userAgentSuffix": "string",
                    "timeout": 60,
                    "enableCircularRedirects": false,
                    "enableCookies": false
                }
            },
            "docker": {
                "v1Enabled": false,
                "forceBasicAuth": true,
                "httpPort": 8082
            },
            "dockerProxy": {
                "indexType": "HUB"
            }
        }' && echo " ✅ docker-proxy created successfully" || echo " ⚠️  docker-proxy may already exist"

    echo ""
}

# Function to create Docker group repository
create_docker_group() {
    echo "Step 3: Creating docker-group repository (port 8084)..."

    curl -X POST "${NEXUS_URL}/service/rest/v1/repositories/docker/group" \
        -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "docker-group",
            "online": true,
            "storage": {
                "blobStoreName": "default",
                "strictContentTypeValidation": true
            },
            "group": {
                "memberNames": [
                    "docker-hosted",
                    "docker-proxy"
                ]
            },
            "docker": {
                "v1Enabled": false,
                "forceBasicAuth": true,
                "httpPort": 8084
            }
        }' && echo " ✅ docker-group created successfully" || echo " ⚠️  docker-group may already exist"

    echo ""
}

# Create repositories
create_docker_hosted
create_docker_proxy
create_docker_group

# Verify repositories
echo "Step 4: Verifying Docker repositories..."
echo ""
curl -s -u "${NEXUS_USER}:${NEXUS_PASS}" \
    "${NEXUS_URL}/service/rest/v1/repositories" | \
    jq -r '.[] | select(.format=="docker") | "\(.name) - \(.type) - Port: \(.attributes.docker.httpPort // "N/A")"'

echo ""
echo "========================================="
echo "Docker Repositories Setup Complete!"
echo "========================================="
echo ""
echo "Registry URLs:"
echo "  - Docker Hosted (push):  ${NEXUS_HOST}:8083"
echo "  - Docker Proxy (cache):  ${NEXUS_HOST}:8082"
echo "  - Docker Group (pull):   ${NEXUS_HOST}:8084"
echo ""
echo "Test Docker login:"
echo "  docker login ${NEXUS_HOST}:8083 -u cicd-user -p CiCd-NexUs-2026"
echo ""
echo "========================================="
