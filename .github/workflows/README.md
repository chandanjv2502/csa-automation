# CSA Automation - GitHub Actions Workflows

This directory contains GitHub Actions workflows for the CSA Automation project, enabling **independent releases** for each service.

---

## Workflow Structure

### Individual Service Workflows (9 Total)

Each service has its own dedicated workflow that builds, pushes to Nexus, and deploys independently:

| Workflow File | Service | Trigger |
|--------------|---------|---------|
| `deploy-frontend-ui.yml` | Frontend UI | Push to `src/frontend-ui/**` or `helm/frontend-ui/**` |
| `deploy-contract-discovery.yml` | Contract Discovery | Push to `src/contract-discovery/**` or `helm/contract-discovery/**` |
| `deploy-contract-ingestion.yml` | Contract Ingestion | Push to `src/contract-ingestion/**` or `helm/contract-ingestion/**` |
| `deploy-ai-extraction.yml` | AI Extraction | Push to `src/ai-extraction/**` or `helm/ai-extraction/**` |
| `deploy-csa-routing.yml` | CSA Routing | Push to `src/csa-routing/**` or `helm/csa-routing/**` |
| `deploy-siren-load.yml` | Siren Load | Push to `src/siren-load/**` or `helm/siren-load/**` |
| `deploy-notification-service.yml` | Notification Service | Push to `src/notification-service/**` or `helm/notification-service/**` |
| `deploy-mock-phoenix-api.yml` | Mock Phoenix API | Push to `src/mock-phoenix-api/**` or `helm/mock-phoenix-api/**` |
| `deploy-mock-siren-api.yml` | Mock Siren API | Push to `src/mock-siren-api/**` or `helm/mock-siren-api/**` |

### Master Deployment Workflow

| Workflow File | Purpose | Trigger |
|--------------|---------|---------|
| `deploy.yml` | Deploy all 9 services | Push to `main` branch or manual workflow dispatch |

---

## How Independent Releases Work

### Automatic Triggers (Path-Based)

Each service workflow is triggered **only when code in its specific directory changes**:

```yaml
on:
  push:
    branches:
      - main
    paths:
      - 'src/<service-name>/**'
      - 'helm/<service-name>/**'
      - '.github/workflows/deploy-<service-name>.yml'
```

**Example:**
- Commit changes to `src/frontend-ui/app.py` → **Only** `deploy-frontend-ui.yml` runs
- Commit changes to `src/contract-discovery/main.py` → **Only** `deploy-contract-discovery.yml` runs
- Commit changes to both `src/frontend-ui/` and `src/ai-extraction/` → **Both workflows run independently**

### Manual Triggers

All workflows support manual execution via `workflow_dispatch`:

```bash
# Trigger specific service deployment
gh workflow run "Deploy Frontend UI"
gh workflow run "Deploy Contract Discovery"

# Trigger all services deployment
gh workflow run "Deploy to EKS"
```

**Via GitHub UI:**
1. Go to: `https://github.com/<your-org>/csa-automation/actions`
2. Select workflow (e.g., "Deploy Frontend UI")
3. Click "Run workflow" button
4. Select branch and click "Run workflow"

---

## Workflow Steps

Each individual service workflow follows this pattern:

### 1. Configure Docker for Insecure Registry
```yaml
- name: Configure Docker for insecure registry
  run: |
    echo '{"insecure-registries": ["44.202.63.187:8083"]}' | sudo tee /etc/docker/daemon.json
    sudo systemctl restart docker
    sleep 5
```

### 2. Login to Nexus
```yaml
- name: Login to Nexus
  run: |
    echo "========================================="
    echo "Logging into Nexus Registry: 44.202.63.187:8083"
    echo "Username: ${{ secrets.NEXUS_USERNAME }}"
    echo "========================================="
    echo "${{ secrets.NEXUS_PASSWORD }}" | docker login 44.202.63.187:8083 \
      --username ${{ secrets.NEXUS_USERNAME }} \
      --password-stdin
```

### 3. Checkout Code
```yaml
- name: Checkout code
  uses: actions/checkout@v3
```

### 4. Build and Push Docker Image
```yaml
- name: Build and push Docker image to Nexus
  env:
    NEXUS_REGISTRY: "44.202.63.187:8083"
    SERVICE: "<service-name>"
    VERSION: "1.0.0"
  run: |
    docker build -t $NEXUS_REGISTRY/csa/$SERVICE:$VERSION \
                 -t $NEXUS_REGISTRY/csa/$SERVICE:latest \
                 ./src/$SERVICE/
    docker push $NEXUS_REGISTRY/csa/$SERVICE:$VERSION
    docker push $NEXUS_REGISTRY/csa/$SERVICE:latest
```

### 5. Configure AWS Credentials
```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v2
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: ${{ secrets.AWS_REGION }}
```

### 6. Update Kubeconfig
```yaml
- name: Update kubeconfig
  run: |
    aws eks update-kubeconfig \
      --name ${{ secrets.EKS_CLUSTER_NAME }} \
      --region ${{ secrets.AWS_REGION }}
```

### 7. Deploy with Helm
```yaml
- name: Deploy <service-name> using Helm
  run: |
    helm upgrade --install <service-name> ./helm/<service-name> \
      --namespace csa-clone \
      --timeout 5m
```

### 8. Verify Deployment
```yaml
- name: Verify deployment
  run: |
    kubectl rollout status deployment/<service-name> -n csa-clone --timeout=2m
    kubectl get pods -n csa-clone -l app=<service-name>
    kubectl get service <service-name> -n csa-clone
```

---

## Benefits of Independent Releases

### 1. **Faster Deployments**
- Only build and deploy the service that changed
- No need to rebuild/redeploy all 9 services for a single change
- Reduced CI/CD pipeline execution time

### 2. **Isolated Failures**
- If one service deployment fails, others are unaffected
- Easy to identify which service caused the failure
- Quick rollback of individual services

### 3. **Parallel Development**
- Multiple teams can work on different services simultaneously
- No deployment conflicts or queue waiting
- Each service maintains its own release cadence

### 4. **Clear Audit Trail**
- GitHub Actions logs show exactly which service was deployed
- Easy to track deployment history per service
- Simplified debugging and troubleshooting

### 5. **Environment-Specific Control**
- Can deploy specific services to specific environments
- Test individual services in UAT before production
- Gradual rollout strategies per service

---

## Required GitHub Secrets

All workflows require these secrets to be configured:

| Secret Name | Description | Example Value |
|------------|-------------|---------------|
| `NEXUS_USERNAME` | Nexus registry username | `cicd-user` |
| `NEXUS_PASSWORD` | Nexus registry password | `CiCd-NexUs-2026` |
| `AWS_ACCESS_KEY_ID` | AWS access key for nextera-clone | `AKIAXXXXXXXXXXXXXXXX` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `EKS_CLUSTER_NAME` | EKS cluster name | `csa-clone-eks` |
| `K8S_NAMESPACE` | Kubernetes namespace | `csa-clone` |

**Configure secrets at:**
`https://github.com/<your-org>/csa-automation/settings/secrets/actions`

---

## Usage Examples

### Example 1: Deploy Only Frontend UI

**Scenario:** Fixed a bug in the frontend UI component.

**Steps:**
1. Make changes to `src/frontend-ui/app.py`
2. Commit and push:
   ```bash
   git add src/frontend-ui/app.py
   git commit -m "Fix: Correct display issue in dashboard"
   git push origin main
   ```
3. **Result:** Only `deploy-frontend-ui.yml` workflow runs
4. **Time:** ~2-3 minutes (vs. 15-20 minutes for all services)

### Example 2: Deploy Multiple Services

**Scenario:** Updated contract discovery and AI extraction services.

**Steps:**
1. Make changes to both services:
   ```bash
   git add src/contract-discovery/ src/ai-extraction/
   git commit -m "Enhance contract extraction logic"
   git push origin main
   ```
2. **Result:** Both `deploy-contract-discovery.yml` and `deploy-ai-extraction.yml` run **in parallel**
3. **Time:** ~3-4 minutes (parallel execution)

### Example 3: Manual Deployment of Specific Service

**Scenario:** Need to redeploy notification service without code changes (e.g., configuration update).

**Steps:**
1. Go to GitHub Actions: `https://github.com/<your-org>/csa-automation/actions`
2. Select "Deploy Notification Service" workflow
3. Click "Run workflow"
4. Select `main` branch
5. Click "Run workflow" button
6. **Result:** Notification service rebuilds and redeploys

### Example 4: Deploy All Services

**Scenario:** Major release requiring all services to be updated.

**Option A - Use Master Workflow:**
```bash
gh workflow run "Deploy to EKS"
```

**Option B - Manual Trigger All:**
```bash
for service in frontend-ui contract-discovery contract-ingestion ai-extraction \
               csa-routing siren-load notification-service mock-phoenix-api mock-siren-api; do
  gh workflow run "Deploy $(echo $service | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g')"
done
```

---

## Workflow Monitoring

### View Running Workflows
```bash
# List all workflow runs
gh run list

# List runs for specific workflow
gh run list --workflow="Deploy Frontend UI"

# Watch a specific run
gh run watch <run-id>
```

### View Workflow Logs
```bash
# View logs for latest run
gh run view --log

# View logs for specific run
gh run view <run-id> --log

# View failed job logs only
gh run view <run-id> --log-failed
```

### Check Deployment Status in Kubernetes
```bash
# Check all pods in csa-clone namespace
kubectl get pods -n csa-clone

# Check specific service
kubectl get pods -n csa-clone -l app=frontend-ui

# Check deployment rollout status
kubectl rollout status deployment/frontend-ui -n csa-clone

# View Helm releases
helm list -n csa-clone
```

---

## Troubleshooting

### Workflow Fails at Docker Login

**Error:**
```
Error response from daemon: login attempt to http://44.202.63.187:8083/v2/ failed with status: 401 Unauthorized
```

**Solution:**
1. Verify cicd-user exists in Nexus (see `how_to_setup_nexus.md`)
2. Update GitHub secrets with correct credentials
3. Retry workflow

### Workflow Fails at Image Push

**Error:**
```
unauthorized: access to the requested resource is not authorized
```

**Solution:**
1. Check cicd-user has `nx-admin` role in Nexus
2. Verify Docker repository exists on port 8083
3. Test credentials: `curl -u cicd-user:CiCd-NexUs-2026 http://44.202.63.187:8083/v2/`

### Helm Deployment Fails

**Error:**
```
Error: timed out waiting for the condition
```

**Solution:**
1. Check EKS cluster is accessible: `kubectl get nodes`
2. Verify namespace exists: `kubectl get namespace csa-clone`
3. Check pod logs: `kubectl logs -n csa-clone -l app=<service-name>`
4. Verify ImagePullSecret exists: `kubectl get secret nexus-registry-secret -n csa-clone`

---

## Best Practices

### 1. **Test Locally Before Pushing**
```bash
# Build Docker image locally
docker build -t 44.202.63.187:8083/csa/frontend-ui:test ./src/frontend-ui/

# Test Helm deployment (dry-run)
helm upgrade --install frontend-ui ./helm/frontend-ui \
  --namespace csa-clone \
  --dry-run --debug
```

### 2. **Use Feature Branches for Testing**
- Create feature branch for changes
- Test workflow on feature branch first
- Merge to main only after verification

### 3. **Monitor Workflow Execution**
- Always check workflow logs after push
- Verify deployment succeeded in Kubernetes
- Test application functionality after deployment

### 4. **Version Management**
- Current version is hardcoded as `1.0.0` in workflows
- Consider using Git commit SHA or tags for versioning
- Example: `VERSION: "${{ github.sha }}"`

### 5. **Rollback Strategy**
```bash
# View Helm release history
helm history <service-name> -n csa-clone

# Rollback to previous version
helm rollback <service-name> <revision> -n csa-clone
```

---

## Next Steps

1. ✅ Individual service workflows created
2. ✅ Path-based triggers configured
3. ✅ Nexus login logging added
4. ⏳ Test individual service deployments
5. ⏳ Implement semantic versioning
6. ⏳ Add workflow badges to main README
7. ⏳ Set up Slack/email notifications for workflow failures

---

## References

- **Nexus Setup Guide:** `../how_to_setup_nexus.md`
- **Action Log:** `../Action.md`
- **GitHub Actions Documentation:** https://docs.github.com/en/actions
- **Helm Documentation:** https://helm.sh/docs/
