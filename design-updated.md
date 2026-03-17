# Complete CSA Automation Architecture (Updated - No API Gateway)

## 1. High-Level Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          NextEra AWS Cloud (VPC)                             │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────┐                 │
│  │   Application Load Balancer (ALB)                       │                 │
│  │   - Created by AWS Load Balancer Controller             │                 │
│  │   - AWS Cognito Authentication                          │                 │
│  │   - SSL/TLS Termination (HTTPS)                         │                 │
│  │   - Routes traffic to Frontend pod only                 │                 │
│  └────────────────────┬────────────────────────────────────┘                 │
│                       │ (HTTPS)                                              │
│  ┌────────────────────▼─────────────────────────────────────────────────┐   │
│  │                      Amazon EKS Cluster                               │   │
│  │                     (Private Subnets)                                 │   │
│  │                                                                        │   │
│  │  ┌──────────────┐                                                     │   │
│  │  │ Frontend     │ ← ONLY pod exposed via ALB                          │   │
│  │  │ (React+Nginx)│                                                     │   │
│  │  └──────┬───────┘                                                     │   │
│  │         │ (Internal K8s DNS calls to backend services)                │   │
│  │         │                                                             │   │
│  │  ┌──────▼───────┐   ┌──────────────┐   ┌──────────────┐             │   │
│  │  │ Contract     │   │ Contract     │   │ AI Extraction│             │   │
│  │  │ Discovery    │   │ Ingestion    │   │ Service      │             │   │
│  │  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘             │   │
│  │         │                   │                   │                      │   │
│  │  ┌──────▼───────┐   ┌───────▼──────┐   ┌──────▼───────┐             │   │
│  │  │ CSA Routing  │   │ Siren Load   │   │ Notification │             │   │
│  │  │ Service      │   │ Service      │   │ Service      │             │   │
│  │  └──────────────┘   └──────────────┘   └──────────────┘             │   │
│  │                                                                        │   │
│  │  ┌──────────────┐   ┌──────────────┐                                 │   │
│  │  │ Mock Phoenix │   │ Mock Siren   │                                 │   │
│  │  │ API (POC)    │   │ API (POC)    │                                 │   │
│  │  └──────────────┘   └──────────────┘                                 │   │
│  │                                                                        │   │
│  │  📍 All backend services: ClusterIP (internal only, not internet)     │   │
│  │  📍 Service-to-service: Kubernetes DNS (http://service.namespace)     │   │
│  │  📍 No API Gateway needed - direct pod-to-pod communication           │   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                               │
│  ┌────────────────┐   ┌────────────────┐   ┌────────────────┐              │
│  │  AWS SQS       │   │  RDS Postgres  │   │  S3 Bucket     │              │
│  │  (5 Queues)    │   │  (Single DB)   │   │  (Contracts)   │              │
│  └────────────────┘   └────────────────┘   └────────────────┘              │
│                                                                               │
│  ┌────────────────┐   ┌────────────────┐   ┌────────────────┐              │
│  │ Secrets Mgr    │   │ SSM Parameter  │   │  CloudWatch    │              │
│  │ (Creds/Keys)   │   │ Store (Config) │   │  (Monitoring)  │              │
│  └────────────────┘   └────────────────┘   └────────────────┘              │
│                                                                               │
│  ┌────────────────┐   ┌────────────────┐                                    │
│  │ AWS Cognito    │   │ AWS Load       │                                    │
│  │ User Pool      │   │ Balancer       │  (Controller runs in kube-system)  │
│  │ (Auth)         │   │ Controller     │                                    │
│  └────────────────┘   └────────────────┘                                    │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Key Architecture Changes from Original:
1. ❌ **Removed:** Kong API Gateway pod (not needed for POC)
2. ✅ **Added:** AWS Cognito authentication at ALB level
3. ✅ **Added:** AWS Load Balancer Controller (manages ALB via Kubernetes Ingress)
4. ✅ **Simplified:** Frontend calls backend services directly via Kubernetes internal DNS

---

## 2. Complete Pod Architecture (9 Pods - Simplified)

### 2.1 Frontend Layer

| Pod         | Purpose                          | Image                                 | Resources            | Port | Exposed To |
|-------------|----------------------------------|---------------------------------------|----------------------|------|------------|
| frontend-ui | React SPA served by Nginx server | nexus.nextera.com/csa/frontend:v1.0.0 | 200m CPU / 256Mi RAM | 80   | ALB (external) |

**Important:**
- "Nginx" here means **Nginx web server inside the container** (serves static React files)
- This is NOT the same as "NGINX Ingress Controller"
- The **Ingress Controller** is AWS Load Balancer Controller (not NGINX)

---

### 2.2 Gateway Layer

~~| Pod         | Purpose                                         | Image                                    | Resources            | Port |~~
~~|-------------|-------------------------------------------------|------------------------------------------|----------------------|------|~~
~~| api-gateway | Kong API Gateway (routing, auth, rate limiting) | nexus.nextera.com/csa/api-gateway:v1.0.0 | 500m CPU / 512Mi RAM | 8000 |~~

**❌ REMOVED - Not needed for POC**

**Why removed:**
- Authentication handled by AWS Cognito at ALB
- Routing handled by Kubernetes Services (ClusterIP)
- Rate limiting not required for POC
- Saves 500m CPU / 512Mi RAM

---

### 2.3 Core Services (6 Microservices)

| Pod                  | Purpose                                             | Image                                           | Resources            | SQS Queues                                              | Service Type |
|----------------------|-----------------------------------------------------|-------------------------------------------------|----------------------|---------------------------------------------------------|--------------|
| contract-discovery   | Polls Phoenix API daily, publishes to SQS           | nexus.nextera.com/csa/contract-discovery:v1.0.0 | 300m CPU / 512Mi RAM | Publishes to discovery-queue                            | ClusterIP    |
| contract-ingestion   | Downloads PDFs from Phoenix, saves to S3, publishes | nexus.nextera.com/csa/contract-ingestion:v1.0.0 | 400m CPU / 1Gi RAM   | Consumes discovery-queue, publishes to ingestion-queue  | ClusterIP    |
| ai-extraction        | Claude API extraction with confidence scoring       | nexus.nextera.com/csa/ai-extraction:v1.0.0      | 1000m CPU / 2Gi RAM  | Consumes ingestion-queue, publishes to extraction-queue | ClusterIP    |
| csa-routing          | Decision logic (new vs update), publishes to Siren  | nexus.nextera.com/csa/csa-routing:v1.0.0        | 300m CPU / 512Mi RAM | Consumes extraction-queue, publishes to routing-queue   | ClusterIP    |
| siren-load           | Loads extracted data into Siren API                 | nexus.nextera.com/csa/siren-load:v1.0.0         | 300m CPU / 512Mi RAM | Consumes routing-queue                                  | ClusterIP    |
| notification-service | WebSocket server + email sender (configurable)      | nexus.nextera.com/csa/notification:v1.0.0       | 200m CPU / 256Mi RAM | Consumes notification-queue                             | ClusterIP    |

**All backend services use ClusterIP:**
- Not exposed to internet
- Only accessible within Kubernetes cluster
- Frontend calls them via internal DNS: `http://contract-discovery.csa-dev-ns.svc.cluster.local:8080`

---

### 2.4 Mock Services (POC Only)

| Pod              | Purpose                                 | Image                                     | Resources            | Port | Service Type |
|------------------|-----------------------------------------|-------------------------------------------|----------------------|------|--------------|
| mock-phoenix-api | Returns mock contracts JSON             | nexus.nextera.com/csa/mock-phoenix:v1.0.0 | 100m CPU / 128Mi RAM | 8080 | ClusterIP    |
| mock-siren-api   | Accepts CSA data, returns mock response | nexus.nextera.com/csa/mock-siren:v1.0.0   | 100m CPU / 128Mi RAM | 8081 | ClusterIP    |

---

### Summary

**Total Pod Count:** 9 pods (reduced from 10)
**Total CPU:** ~3.1 cores (down from ~3.6 cores)
**Total RAM:** ~6 GB (down from ~6.5 GB)

---

## 3. Ingress Configuration (AWS ALB with Cognito)

### 3.1 Kubernetes Ingress Resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: csa-frontend-ingress
  namespace: csa-dev-ns
  annotations:
    # ALB Configuration
    alb.ingress.kubernetes.io/scheme: internet-facing  # or 'internal' for VPN-only
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERT_ID

    # AWS Cognito Authentication
    alb.ingress.kubernetes.io/auth-type: cognito
    alb.ingress.kubernetes.io/auth-idp-cognito-user-pool-arn: arn:aws:cognito-idp:us-east-1:ACCOUNT_ID:userpool/POOL_ID
    alb.ingress.kubernetes.io/auth-idp-cognito-user-pool-client-id: "CLIENT_ID"
    alb.ingress.kubernetes.io/auth-idp-cognito-user-pool-domain: "csa-nextera"
    alb.ingress.kubernetes.io/auth-on-unauthenticated-request: authenticate
    alb.ingress.kubernetes.io/auth-scope: "openid email profile"

    # Health Checks
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
    alb.ingress.kubernetes.io/success-codes: "200"

    # Tags
    alb.ingress.kubernetes.io/tags: Environment=dev,Project=CSA,Application=csa-automation

spec:
  ingressClassName: alb
  rules:
  - host: csa.devrisk.ne.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-ui
            port:
              number: 80
```

**What happens:**
1. User visits `https://csa.devrisk.ne.com`
2. ALB redirects to Cognito login page
3. User logs in with credentials
4. Cognito redirects back to ALB
5. ALB forwards to frontend-ui Service (ClusterIP)
6. Frontend pod serves React application

---

### 3.2 Frontend Service (ClusterIP)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-ui
  namespace: csa-dev-ns
spec:
  type: ClusterIP  # Internal only
  selector:
    app: frontend-ui
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
```

---

### 3.3 Backend Services (All ClusterIP)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: contract-discovery
  namespace: csa-dev-ns
spec:
  type: ClusterIP  # NOT exposed to internet
  selector:
    app: contract-discovery
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
```

**Frontend calls backend via Kubernetes DNS:**
```javascript
// In React frontend code
const response = await fetch('http://contract-discovery.csa-dev-ns.svc.cluster.local:8080/api/contracts');
// Or simplified (if in same namespace):
const response = await fetch('http://contract-discovery:8080/api/contracts');
```

---

## 4. Complete Data Flow (Updated - No API Gateway)

### Phase 1: Contract Discovery (Daily Scheduled Job)

**Step 1:** Scheduled Trigger (CronJob)
- contract-discovery pod wakes up at 2:00 AM UTC daily
- Calls Mock Phoenix API: `GET /api/contracts?updated_since=<yesterday>`
- Receives JSON: `[{"contract_id": "PHX-001", "url": "...", "counterparty": "..."}]`

**Step 2:** Publish to SQS Discovery Queue
- For each contract in response:
  - Validate contract_id exists
  - Insert into PostgreSQL contracts table (status='discovered')
  - Send message to `csa-dev-discovery` queue
  - Log audit trail to PostgreSQL

---

### Phase 2: Contract Ingestion (Event-Driven)

**Step 3:** Contract Ingestion Pod Consumes SQS
- contract-ingestion pod polls `csa-dev-discovery` queue
- Downloads PDF from phoenix_url
- Validates PDF is readable

**Step 4:** Upload to S3 and Database Update
- Upload PDF to S3: `s3://nextera-csa-dev/contracts/2026/03/PHX-001.pdf`
- Update PostgreSQL contracts table: status = 'ingested'
- Delete message from queue

**Step 5:** Publish to Extraction Queue
- Send message to `csa-dev-ingestion` queue
- Send notification to `csa-dev-notification` queue

---

### Phase 3-6: [Same as before - AI Extraction, Routing, Siren Load, Notifications]

---

## 5. AWS Services Integration Summary

| AWS Service                  | Usage                                         | Access Method                                     |
|------------------------------|-----------------------------------------------|---------------------------------------------------|
| EKS                          | Hosts all 9 pods                              | N/A (cluster itself)                              |
| ALB                          | Ingress for frontend UI (with Cognito auth)   | AWS Load Balancer Controller (Kubernetes)         |
| AWS Cognito User Pool        | User authentication                           | ALB annotation integration                        |
| RDS PostgreSQL               | Single database for all tables                | IAM role attached to service account              |
| S3                           | Stores contract PDFs                          | IAM role with s3:PutObject, s3:GetObject          |
| SQS                          | 5 queues + 1 DLQ for async messaging          | IAM role with sqs:SendMessage, sqs:ReceiveMessage |
| Secrets Manager              | Stores DB password, API keys                  | Pod retrieves at startup via IAM role             |
| SSM Parameter Store          | Stores non-sensitive config (S3 bucket names) | Pod retrieves at startup                          |
| CloudWatch                   | Logs, metrics, alarms                         | Fluent Bit sidecar sends logs                     |
| AWS Load Balancer Controller | Creates/manages ALB from Ingress resource     | Pod running in kube-system namespace              |

---

## 6. IAM Roles for Service Accounts (IRSA) - Required

### 6.1 Frontend Service Account (No AWS permissions needed)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: frontend-sa
  namespace: csa-dev-ns
# No IAM role annotation - frontend only serves static files
```

---

### 6.2 Backend Service Accounts (AWS permissions required)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: contract-discovery-sa
  namespace: csa-dev-ns
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/CSA-ContractDiscovery-Role
```

**IAM Role Policy for contract-discovery:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["sqs:SendMessage"],
      "Resource": "arn:aws:sqs:us-east-1:ACCOUNT_ID:csa-dev-discovery"
    },
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:/csa/dev/*"
    }
  ]
}
```

**Similar ServiceAccounts needed for:**
- contract-ingestion-sa (S3 read/write, SQS, Secrets Manager)
- ai-extraction-sa (S3 read, SQS, Secrets Manager for Claude API key)
- csa-routing-sa (SQS)
- siren-load-sa (SQS, Secrets Manager for Siren API key)
- notification-service-sa (SQS, SES for sending emails)

---

## 7. Estimated Processing Times

| Phase                      | Time          | Bottleneck                 |
|----------------------------|---------------|----------------------------|
| Discovery (daily batch)    | 5-10 seconds  | Phoenix API response       |
| Ingestion per contract     | 2-5 seconds   | PDF download + S3 upload   |
| AI Extraction per contract | 10-30 seconds | Claude API latency         |
| Routing per contract       | 1-2 seconds   | Siren API lookup           |
| Siren Load per contract    | 2-5 seconds   | Siren API POST             |
| **Total per contract**     | **15-42 seconds** | Dominated by AI extraction |

POC Throughput: For 10 contracts/day discovered, all complete within 5-7 minutes.

---

## 8. Cost Estimate (POC Phase - 6 Weeks)

| Resource                   | Cost                         | Notes                          |
|----------------------------|------------------------------|--------------------------------|
| EKS cluster (existing)     | $0 (shared)                  | Using NextEra's existing cluster |
| RDS PostgreSQL db.t3.small | ~$30/month                   |                                |
| S3 storage (10 GB)         | ~$0.23/month                 |                                |
| AWS SQS                    | ~$0 (first 1M requests free) | POC volume << 1M messages/month |
| CloudWatch logs (5 GB)     | ~$2.50/month                 |                                |
| ALB                        | ~$16/month                   | $0.0225/hour + LCU charges     |
| AWS Cognito                | ~$0 (first 50K MAUs free)    | POC << 50K users               |
| **Total POC Cost**         | **~$49/month**               | **Savings from removing Kong: $16/month** |

---

## 9. Security Architecture

### 9.1 Network Security (Layered)

```
Layer 1: Network Isolation
├─ Backend services: ClusterIP only (not accessible from internet)
└─ Only frontend exposed via ALB

Layer 2: ALB Authentication
├─ AWS Cognito authentication required
└─ Only authorized users can access frontend

Layer 3: Frontend Authorization
├─ React UI checks user permissions
└─ UI hides features user doesn't have access to

Layer 4: Backend Authorization (CRITICAL!)
├─ Each API endpoint validates user permissions
├─ Check Active Directory groups or Cognito claims
└─ Return 403 Forbidden if unauthorized

Layer 5: Kubernetes Network Policies (Optional)
├─ Restrict pod-to-pod communication
└─ Only allow frontend → backend traffic
```

---

### 9.2 Example Backend Authorization

```python
# In contract-discovery FastAPI service
from fastapi import FastAPI, Header, HTTPException

app = FastAPI()

AUTHORIZED_USERS = [
    'analyst1@nextera.com',
    'analyst2@nextera.com',
    'manager@nextera.com'
]

@app.get("/api/contracts")
async def get_contracts(x_amzn_oidc_identity: str = Header(None)):
    # ALB passes user email in header after Cognito authentication
    user_email = x_amzn_oidc_identity

    if user_email not in AUTHORIZED_USERS:
        raise HTTPException(status_code=403, detail="Not authorized")

    # Proceed with business logic
    return {"contracts": [...]}
```

---

## 10. Key Differences from Original Design

| Aspect | Original Design | Updated Design | Reason for Change |
|--------|-----------------|----------------|-------------------|
| **Pod Count** | 10 pods | 9 pods | Removed Kong API Gateway |
| **Authentication** | Not specified | AWS Cognito at ALB | Security requirement |
| **Ingress Controller** | Not specified | AWS Load Balancer Controller | Standard for EKS + ALB |
| **External Access** | ALB → Kong → Frontend | ALB → Frontend (direct) | Simplified for POC |
| **Backend Routing** | Through Kong | Direct via K8s DNS | Simpler, no API Gateway needed |
| **Service Types** | Not specified | All ClusterIP (except frontend) | Security best practice |
| **CPU/RAM** | 3.6 cores / 6.5 GB | 3.1 cores / 6 GB | Savings from removing Kong |
| **Cost** | ~$33/month | ~$49/month | Added ALB + Cognito costs |

---

## 11. Deployment Flow

### Step 1: Prerequisites (NextEra provides)
- AWS Load Balancer Controller installed in EKS
- AWS Cognito User Pool created
- IAM roles for service accounts (IRSA)
- SSL certificate in ACM
- Domain name (e.g., csa.devrisk.ne.com)

### Step 2: Deploy Kubernetes Resources
```bash
# Deploy all resources
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/serviceaccounts.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/deployments/
kubectl apply -f k8s/services/
kubectl apply -f k8s/ingress.yaml
```

### Step 3: Get ALB DNS Name
```bash
kubectl get ingress csa-frontend-ingress -n csa-dev-ns \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Output: k8s-csadevns-abc123.us-east-1.elb.amazonaws.com
```

### Step 4: Create DNS Record (NextEra DNS team)
```
Type: CNAME
Name: csa.devrisk.ne.com
Value: k8s-csadevns-abc123.us-east-1.elb.amazonaws.com
TTL: 300
```

### Step 5: Test Access
```
https://csa.devrisk.ne.com
→ Redirects to Cognito login
→ User logs in
→ Redirects back to CSA frontend
→ Application loads
```

---

## 12. Summary

**Simplified Architecture for POC:**
- ✅ 9 pods (removed Kong API Gateway)
- ✅ AWS Cognito authentication at ALB
- ✅ All backend services internal (ClusterIP)
- ✅ Direct pod-to-pod communication via Kubernetes DNS
- ✅ AWS Load Balancer Controller manages ALB
- ✅ Saves resources and complexity while maintaining security

**Key Security Features:**
- Multi-layer security (network, ALB auth, backend auth)
- Zero trust model (backend validates all requests)
- Audit trail for all operations
- Secrets managed via AWS Secrets Manager

**Ready for POC deployment with NextEra's EKS infrastructure!**
