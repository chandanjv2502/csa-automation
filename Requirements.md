# Github and CI-CD

## Assumptions

NextEra provides a repository for CSA automation in their NextEra-Github-Organization and provide access to Dsider team members.

NextEra has a established CI-CD pipeline to build docker images and deploying to EKS.

NextEra has created a namespace for CSA automation in their EKS.

Is the CSA-automation application ALB be internet-facing or internal(accessed in VPN)?

## Dsider will need to write workflows to

a. Build Docker images and push to Nexus

b. Deploy Docker images to EKS using Helm(including Ingress resources)

## Preferably

NextEra will share some example GitHub Actions workflows

1. Example Ingress YAML from an existing application deployed in the Dev environment
   - This will help us understand:
     - Which ingress controller you use (AWS ALB, NGINX, etc.)
     - Is the CSA-automation application ALB internet facing or internal(accessed in VPN)
     - Required annotations and configurations
     - SSL/TLS certificate setup
     - Health check configuration
     - Domain naming patterns

2. Specific details we need:
   - What ingressClassName to use?
   - What domain/subdomain pattern for CSA? (e.g., csa.devrisk.ne.com?)
   - Any required tags or labels for compliance?

Example from any app would be helpful - even if it's redacted or simplified. Seeing your real-world Ingress configuration will ensure we follow your standards from the start.

---

## Requirements

1. GitHub Repository Access with Permissions needed to (a) push code (b) Workflow dispatch (to trigger GitHub Actions)

2. Nexus Container Registry Details via Github secrets

3. EKS Namespace details
   - Namespace name: (used in workflow for helm upgrade)
   - EKS cluster name: (used in workflow for update-kubeconfig)
   - AWS region: (used in workflow for update-kubeconfig)

4. NextEra creates an IAM user for GitHub Actions and provides credentials to access EKS via secrets

5. Nextera creates an IAM user with Kubernetes RBAC for the Dsider developers to access the pods[view/deploy,describe resources,exec into pods for debugging] limited to the provided namespace (in the dev environment only).

6. Kubernetes Permissions for GitHub Actions can deploy to provided namespace.

   **🚨 CRITICAL: Required Kubernetes RBAC permissions for GitHub Actions deployer**

   These permissions were validated during POC testing and are **minimum required** for Helm-based deployments:

   - API Group: `""` (core) → Resources: `pods, services, secrets, serviceaccounts` → Verbs: `get, list, watch, create, update, patch, delete`
   - API Group: `apps` → Resources: `deployments, replicasets` → Verbs: `get, list, watch, create, update, patch, delete`
   - API Group: `networking.k8s.io` → Resources: `ingresses` → Verbs: `get, list, watch, create, update, patch, delete`

   **Why These Permissions Are Required:**
   - `secrets`: **CRITICAL** - Helm stores release metadata as Kubernetes Secrets. Without this permission, deployments will fail with "secrets is forbidden" error
   - `serviceaccounts`: Required for creating pod ServiceAccounts with IRSA (IAM Roles for Service Accounts) annotations
   - `pods/services`: Standard resources for application deployments
   - `deployments/replicasets`: Required for managing application workloads
   - `ingresses`: Required for ALB/load balancer configuration

   **Example Kubernetes Role (validated in POC):**
   ```yaml
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata:
     name: csa-deployer
     namespace: csa-poc  # Update to NextEra's namespace
   rules:
   - apiGroups: [""]
     resources: ["services", "pods", "secrets", "serviceaccounts"]
     verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
   - apiGroups: ["apps"]
     resources: ["deployments", "replicasets"]
     verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
   - apiGroups: ["networking.k8s.io"]
     resources: ["ingresses"]
     verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: RoleBinding
   metadata:
     name: csa-deployer-binding
     namespace: csa-poc  # Update to NextEra's namespace
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: Role
     name: csa-deployer
   subjects:
   - apiGroup: rbac.authorization.k8s.io
     kind: Group
     name: csa-deployers  # This group name must match aws-auth mapping
   ```

   **IAM to Kubernetes Group Mapping (aws-auth ConfigMap):**

   NextEra needs to add this mapping to the `aws-auth` ConfigMap in `kube-system` namespace:

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: aws-auth
     namespace: kube-system
   data:
     mapUsers: |
       - userarn: arn:aws:iam::<NEXTERA-ACCOUNT-ID>:user/<CICD-IAM-USER>
         username: <CICD-IAM-USER>
         groups:
         - csa-deployers  # This group name must match RoleBinding subject
   ```

   **Verification Commands:**
   ```bash
   # Verify permissions after setup
   kubectl auth can-i create secrets -n csa-poc --as=<CICD-IAM-USER>
   kubectl auth can-i create serviceaccounts -n csa-poc --as=<CICD-IAM-USER>
   kubectl auth can-i create deployments -n csa-poc --as=<CICD-IAM-USER>
   ```

   **Reference:** Complete RBAC configuration with detailed documentation is available in `k8s/00-rbac.yaml`

7. Confirm kubectl,aws cli,Helm Installation in GitHub Actions Runner

8. Network Access from
   - GitHub Actions Runners to the EKS cluster and Nexus
   - Docker Registry is Accessible from EKS Cluster

9. Dsider will provide the ALB DNS name for Nextera to create the CNAME record (retrived after ingress.yaml is run as part of helm)

---

# Resources Required for CSA Automation

## RDS PostgreSQL Database

- Instance identifier: csa-poc-postgres-dev
- Engine: PostgreSQL 15.x or 16.x
- Instance class: db.t3.medium (can adjust based on load)
- Storage: 100 GB gp3 (General Purpose SSD)
- Multi-AZ: Yes (for high availability)
- VPC: Same VPC as EKS cluster
- Subnet group: Private subnets (no public access)

RDS username and Password shared via secrets manager

Security group: Allow inbound 5432 from EKS cluster security group

NextEra to share the RDS Endpoint: csa-poc-postgres-dev.<random>.us-east-1.rds.amazonaws.com with Dsider (will be used in Helmcharts,configmap/values.yaml)

---

## S3-Bucket

Nextera to:

Create S3 bucket and apply bucket policies according to governance standards.

Provide the below details (will be required in helm-values.yaml)

### S3 Buckets
- [ ] Confirm bucket names created:proposed: nextera-csa-<env>-documents
- [ ] Region: us-east-1 ((recommended to use by s3-SDK in code))

---

## AWS Secrets Manager Secrets

Nextera creates secrets for the below and corresponding secret names to be shared (will be used by helm-values.yaml):

### Secret Names to Provide:
- [ ] PostgreSQL credentials: _________`csa-poc/dev/<secret-name>`________
- [ ] OpenLink API key: _________________
- [ ] Phoenix API key: _________________
- [ ] Documentum API key: _________________
- [ ] SIREN API key: _________________
- [ ] VectorDB credentials: _________________
- [ ] OCR service API key: _________________

---

## ALB

Is the CSA-automation application ALB be internet-facing or internal?

AWS Load Balancer Controller installed in provided cluster.

Dsider will provide the ALB DNS name for Nextera to create the CNAME record

Load Balancer Controller has Cognito permissions

### 🚨 CRITICAL: VPC Subnet Tagging Requirements

**The AWS Load Balancer Controller requires specific tags on VPC subnets for ALB auto-discovery.**

#### For Internet-Facing ALBs (Public Subnets):

Public subnets must have BOTH of these tags:

1. **Cluster Tag:**
   ```
   Key: kubernetes.io/cluster/<CLUSTER_NAME>
   Value: shared
   ```
   Example: `kubernetes.io/cluster/csa-poc-eks=shared`

2. **Public ELB Role Tag:**
   ```
   Key: kubernetes.io/role/elb
   Value: 1
   ```

#### For Internal ALBs (Private Subnets):

Private subnets must have BOTH of these tags:

1. **Cluster Tag:**
   ```
   Key: kubernetes.io/cluster/<CLUSTER_NAME>
   Value: shared
   ```
   Example: `kubernetes.io/cluster/csa-poc-eks=shared`

2. **Internal ELB Role Tag:**
   ```
   Key: kubernetes.io/role/internal-elb
   Value: 1
   ```

#### Requirements:

- **At least 2 public subnets** in different Availability Zones (for internet-facing ALBs)
- **At least 2 private subnets** in different Availability Zones (for internal ALBs)
- **Cluster name in tags MUST match the actual EKS cluster name exactly**

#### Common Issue:

If subnets are tagged with the wrong cluster name, the Load Balancer Controller will fail with:
```
Failed build model due to couldn't auto-discover subnets: unable to resolve at least one subnet
```

**Verification Command:**
```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query 'Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Tags:Tags}' \
  --output table
```

Cognito User Pool created and below details shared with Dsider team:
- User Pool ARN: (needed for adding values to the ingress annotations)
- User Pool Client ID:(needed for adding values to the Ingress annotations)
- User Pool Domain (needed for adding values to the Ingress annotations)

SSL Certificate ARN (for HTTPS)

Domain name confirmed (csa.devrisk.ne.com)

Reference Ingress YAML (to see NextEra's standard annotations)

Cognito Callback URLs: AWS ALB Cognito integration requires callback URLs in this format:

`https://{domain}/oauth2/idpresponse`

So if CSA domains are:
- Dev: csa.devrisk.ne.com
- UAT: csa.uatrisk.ne.com

Then configure Cognito with:
- https://csa.devrisk.ne.com/oauth2/idpresponse
- https://csa.uatrisk.ne.com/oauth2/idpresponse

### AWS Cognito

Next creates a AWS Cognito user pool and share the below with Dsider team:
- User Pool ARN:
- User Pool Client ID:
- User Pool Domain

Above are needed for adding values to the Ingress annotations.

Assuming :AmazonEKSLoadBalancerControllerRole have the cognito-idp:DescribeUserPoolClient permission?"

---

## IAM Roles for Service Accounts (IRSA)

Assume Nextera to:

1. Create one IAM role that all CSA services will use (via IRSA - IAM Roles for Service Accounts).

### Prerequisites
- EKS cluster: `csa-poc-eks` (must have OIDC provider enabled)
- Namespace: `csa-poc`

example: oidc.eks.us-east-1.amazonaws.com/id/D710E9122A01B7D29B58FB8A6A511CD6

2. Edit below 2 JSON files (trust-policy.json and csa-service-permissions.json):

and replace Placeholders below:
- <AWS_ACCOUNT_ID>: NextEra's AWS account number (e.g., 524997768738)
- <OIDC_PROVIDER_ID>: NextEra's EKS OIDC provider ID (e.g., oidc.eks.us-east-1.amazonaws.com/id/D710E9122A01B7D29B58FB8A6A511CD6)

### File 1: trust-policy.json

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/<OIDC_PROVIDER_ID>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "<OIDC_PROVIDER_ID>:sub": "system:serviceaccount:csa-poc:csa-*"
        },
        "StringEquals": {
          "<OIDC_PROVIDER_ID>:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### File 2: csa-service-permissions.json

Placeholders for NextEra to replace:
- <AWS_ACCOUNT_ID>: NextEra's AWS account number
- <VPC_ENDPOINT_ID>: NextEra's VPC endpoint ID for Textract (optional but recommended)
- Bucket name: Adjust if NextEra uses different naming convention

### Step 3: Create IAM Role using the above trust policy(trust-policy.json) - Obtained Role Arn to be shared with Dsider

Info: Dsider will use the role arn in helm to : annotate in the serviceaccount templates /values.yaml of each services.

### Step 4: Attach Permission Policy to the above role

What this does: Grants permissions to access S3, Textract, Secrets Manager, and CloudWatch.

Optional Enhancement: VPC Endpoint Restriction

If NextEra uses VPC Endpoints for SQS and Textract, you can add network-level security by adding a Condition block to restrict access to only requests coming from your VPC endpoints.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3BucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::nextera-csa-*-documents",
        "arn:aws:s3:::nextera-csa-*-documents/*"
      ]
    },
    {
      "Sid": "SQSQueueAccess",
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ChangeMessageVisibility"
      ],
      "Resource": "arn:aws:sqs:us-east-1:<AWS_ACCOUNT_ID>:csa-poc-*"
    },
    {
      "Sid": "TextractAccess",
      "Effect": "Allow",
      "Action": [
        "textract:AnalyzeDocument",
        "textract:DetectDocumentText"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecretsManagerAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:<AWS_ACCOUNT_ID>:secret:csa-poc/*"
    },
    {
      "Sid": "SSMParameterStoreAccess",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:us-east-1:<AWS_ACCOUNT_ID>:parameter/csa-poc/*"
    },
    {
      "Sid": "CloudWatchLogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:us-east-1:<AWS_ACCOUNT_ID>:log-group:/aws/eks/csa-poc/*"
    },
    {
      "Sid": "CloudWatchMetricsAccess",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "cloudwatch:namespace": "CSA/Application"
        }
      }
    }
  ]
}
```
