# How to Setup Nexus Repository Manager

## Overview

This guide covers the complete setup of Nexus Repository Manager for the CSA Automation project in the nextera-clone environment, starting from EC2 instance creation.

---

## Prerequisites

- AWS CLI configured with `nextera-clone` profile
- SSH key pair for EC2 access
- EKS cluster already created (csa-clone-eks)

---

## Step 1: Launch EC2 Instance for Nexus

### 1.1 Get VPC and Subnet from EKS Cluster

```bash
aws eks describe-cluster \
  --profile nextera-clone \
  --region us-east-1 \
  --name csa-clone-eks \
  --query 'cluster.resourcesVpcConfig.[vpcId,subnetIds[0]]' \
  --output text
```

Save the VPC ID and Subnet ID for next steps.

### 1.2 Create Security Group

```bash
# Create security group
VPC_ID="<your-vpc-id-from-above>"

SG_ID=$(aws ec2 create-security-group \
  --profile nextera-clone \
  --region us-east-1 \
  --group-name nexus-clone-sg \
  --description "Security group for Nexus Repository Manager in nextera-clone" \
  --vpc-id $VPC_ID \
  --output text --query 'GroupId')

echo "Security Group ID: $SG_ID"
```

### 1.3 Add Ingress Rules to Security Group

```bash
# Allow SSH (port 22)
# Allow Nexus UI (port 8081)
# Allow Docker registries (ports 8082, 8083, 8084)
aws ec2 authorize-security-group-ingress \
  --profile nextera-clone \
  --region us-east-1 \
  --group-id $SG_ID \
  --ip-permissions \
    IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0}]' \
    IpProtocol=tcp,FromPort=8081,ToPort=8081,IpRanges='[{CidrIp=0.0.0.0/0}]' \
    IpProtocol=tcp,FromPort=8082,ToPort=8082,IpRanges='[{CidrIp=0.0.0.0/0}]' \
    IpProtocol=tcp,FromPort=8083,ToPort=8083,IpRanges='[{CidrIp=0.0.0.0/0}]' \
    IpProtocol=tcp,FromPort=8084,ToPort=8084,IpRanges='[{CidrIp=0.0.0.0/0}]'
```

### 1.4 Create SSH Key Pair

```bash
# Create key pair and save to ~/.ssh/
aws ec2 create-key-pair \
  --profile nextera-clone \
  --region us-east-1 \
  --key-name nextera-clone-nexus-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/nextera-clone-nexus-key.pem

# Set correct permissions
chmod 400 ~/.ssh/nextera-clone-nexus-key.pem

echo "SSH key saved to: ~/.ssh/nextera-clone-nexus-key.pem"

# Also copy to project folder for easy access
cp ~/.ssh/nextera-clone-nexus-key.pem /Users/chandanjv/Documents/NextEra/Freshsetup/NextEra_Document/Mail_Req/csa-automation/
chmod 400 /Users/chandanjv/Documents/NextEra/Freshsetup/NextEra_Document/Mail_Req/csa-automation/nextera-clone-nexus-key.pem
```

### 1.5 Get Latest Amazon Linux 2023 AMI

```bash
AMI_ID=$(aws ec2 describe-images \
  --profile nextera-clone \
  --region us-east-1 \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)

echo "AMI ID: $AMI_ID"
```

### 1.6 Launch EC2 Instance (t3.small with 2GB RAM)

```bash
SUBNET_ID="<your-subnet-id-from-step-1.1>"

INSTANCE_ID=$(aws ec2 run-instances \
  --profile nextera-clone \
  --region us-east-1 \
  --image-id $AMI_ID \
  --instance-type t3.small \
  --key-name nextera-clone-nexus-key \
  --security-group-ids $SG_ID \
  --subnet-id $SUBNET_ID \
  --associate-public-ip-address \
  --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":30,\"VolumeType\":\"gp3\"}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=nexus-clone},{Key=Project,Value=csa-automation},{Key=Environment,Value=clone}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"
```

### 1.7 Wait for Instance to be Running

```bash
aws ec2 wait instance-running \
  --profile nextera-clone \
  --region us-east-1 \
  --instance-ids $INSTANCE_ID

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --profile nextera-clone \
  --region us-east-1 \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Nexus instance running at: $PUBLIC_IP"
echo "SSH command: ssh -i ~/.ssh/nextera-clone-nexus-key.pem ec2-user@$PUBLIC_IP"
```

---

## Step 2: Install Docker and Nexus

### 2.1 SSH into the Instance

```bash
# SSH using key from ~/.ssh/
ssh -i ~/.ssh/nextera-clone-nexus-key.pem ec2-user@$PUBLIC_IP

# Or from project folder:
# ssh -i /Users/chandanjv/Documents/NextEra/Freshsetup/NextEra_Document/Mail_Req/csa-automation/nextera-clone-nexus-key.pem ec2-user@$PUBLIC_IP
```

### 2.2 Install and Configure Docker

```bash
# Update system
sudo yum update -y

# Install Docker
sudo yum install docker -y

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add ec2-user to docker group
sudo usermod -a -G docker ec2-user

# Create directory for Nexus data
sudo mkdir -p /nexus-data
sudo chown -R 200:200 /nexus-data
```

### 2.3 Run Nexus Container with Reduced Memory

```bash
# Exit and re-login for docker group to take effect
exit
ssh -i ~/.ssh/nextera-clone-nexus-key.pem ec2-user@$PUBLIC_IP

# Run Nexus with memory limits for t3.small (2GB RAM)
sudo docker run -d \
  --name nexus \
  --restart unless-stopped \
  -p 8081:8081 \
  -p 8082:8082 \
  -p 8083:8083 \
  -p 8084:8084 \
  -e INSTALL4J_ADD_VM_PARAMS="-Xms512m -Xmx1536m -XX:MaxDirectMemorySize=512m" \
  -v /nexus-data:/nexus-data \
  sonatype/nexus3:latest
```

### 2.4 Wait for Nexus to Start (2-3 minutes)

```bash
# Check Nexus container status
docker ps

# Follow Nexus logs (Ctrl+C to exit)
docker logs -f nexus

# Wait until you see: "Started Sonatype Nexus"
```

### 2.5 Get Initial Admin Password

```bash
# Wait 2-3 minutes after Nexus starts, then:
sudo cat /nexus-data/admin.password
```

Save this password - you'll need it for initial login.

**Example output:**
```
b1b4d60c-2290-4b16-a466-1d6222e03254
```

---

## Step 3: Access Nexus UI and Complete Setup Wizard

### 3.1 Access Nexus Web UI

- Open browser and go to: `http://<PUBLIC_IP>:8081`
- Example: `http://44.202.63.187:8081`
- Click **Sign In** (top right)

### 3.2 Login with Default Credentials

- **Username:** `admin`
- **Password:** `<password-from-step-2.5>`

### 3.3 Complete Setup Wizard

1. **Welcome screen:**
   - Click **Next**

2. **Change admin password:**
   - New password: `CstgQa-123` (or your choice)
   - Confirm password
   - Click **Next**

3. **Configure Anonymous Access:**
   - **RECOMMENDED FOR PRODUCTION:** Select **Disable anonymous access** (requires authentication for all pulls)
   - This is more secure and requires ImagePullSecrets in Kubernetes
   - Click **Next**

   **Note:** If you disable anonymous access, Kubernetes needs credentials to pull images.
   - ✅ All Helm charts are already configured with `imagePullSecrets: nexus-registry-secret`
   - ✅ Create the secret using: `k8s/create-nexus-secret.sh`

4. **Finish:**
   - Click **Finish**

---

## Step 4: Create CI/CD User

### 4.1 Navigate to User Management

- Click the **gear icon** (⚙️) at the top navigation bar
- Go to **Security** → **Users**

### 4.2 Create New User

- Click **Create local user** button
- Fill in:
  - **ID:** `cicd-user`
  - **First Name:** `CI`
  - **Last Name:** `CD User`
  - **Email:** `cicd@localhost`
  - **Password:** `CiCd-NexUs-2026`
  - **Confirm Password:** `CiCd-NexUs-2026`
  - **Status:** Active
  - **Roles:** Select `nx-admin`
- Click **Create**

### 4.3 Verify User Creation

**IMPORTANT:** Verify the user was created successfully:

```bash
# SSH into Nexus EC2 instance
ssh -i ./nextera-clone-nexus-key.pem ec2-user@44.202.63.187

# Check if cicd-user exists
curl -u admin:CstgQa-123 http://localhost:8081/service/rest/v1/security/users | \
  jq '.[] | select(.userId=="cicd-user")'

# Should return user details. If empty, user was not created.
```

### 4.4 Alternative: Create User via API

If manual UI creation fails or you prefer automation, use the REST API:

```bash
# Create cicd-user via Nexus REST API
ssh -i ./nextera-clone-nexus-key.pem ec2-user@44.202.63.187 'curl -X POST "http://localhost:8081/service/rest/v1/security/users" \
  -u "admin:CstgQa-123" \
  -H "Content-Type: application/json" \
  -d "{
    \"userId\": \"cicd-user\",
    \"firstName\": \"CI\",
    \"lastName\": \"CD User\",
    \"emailAddress\": \"cicd@localhost\",
    \"password\": \"CiCd-NexUs-2026\",
    \"status\": \"active\",
    \"roles\": [\"nx-admin\"]
  }"'
```

**Expected Response:**
```json
{
  "userId": "cicd-user",
  "firstName": "CI",
  "lastName": "CD User",
  "emailAddress": "cicd@localhost",
  "source": "default",
  "status": "active",
  "roles": ["nx-admin"]
}
```

### 4.5 Test User Credentials

```bash
# Test authentication with cicd-user
curl -u "cicd-user:CiCd-NexUs-2026" http://44.202.63.187:8083/v2/

# Should return empty response with exit code 0 (success)
# If you get 401 Unauthorized, the user was not created correctly
```

### 4.6 Save Credentials for GitHub Secrets

- `NEXUS_USERNAME`: `cicd-user`
- `NEXUS_PASSWORD`: `CiCd-NexUs-2026`

---

## Step 5: Create Docker Repositories

### 5.1 Create Docker Hosted Repository (Port 8083)

1. Click **gear icon** (⚙️) → **Repository** → **Repositories**
2. Click **Create repository**
3. Select **docker (hosted)**
4. Configure:
   - **Name:** `docker-hosted`
   - **HTTP:** Check the box, enter port: `8083`
   - **Enable Docker V1 API:** Unchecked
   - **Blob store:** default
   - **Deployment policy:** Allow redeploy
5. Click **Create repository**

### 5.2 Create Docker Proxy Repository (Port 8082) - Optional

1. Click **Create repository**
2. Select **docker (proxy)**
3. Configure:
   - **Name:** `docker-proxy`
   - **HTTP:** Check the box, enter port: `8082`
   - **Remote storage:** `https://registry-1.docker.io`
   - **Docker Index:** Use Docker Hub
   - **Blob store:** default
4. Click **Create repository**

### 5.3 Create Docker Group Repository (Port 8084) - Optional

1. Click **Create repository**
2. Select **docker (group)**
3. Configure:
   - **Name:** `docker-group`
   - **HTTP:** Check the box, enter port: `8084`
   - **Member repositories:** Select:
     1. `docker-hosted`
     2. `docker-proxy`
   - **Blob store:** default
4. Click **Create repository**

---

## Step 6: Update Project Files with Nexus IP

All project files have already been updated with the Nexus registry URL.

**Registry URL:** `<PUBLIC_IP>:8083`

**Files updated:**
- `.github/workflows/*.yml` - GitHub Actions workflows
- `helm/*/values.yaml` - Helm chart image repositories
- `k8s/containerd-config-daemonset.yaml` - Kubernetes containerd config
- `build-and-push.sh` - Build script

---

## Step 7: Configure GitHub Secrets

Add the following secrets to your GitHub repository:

**Go to:** `https://github.com/chandanjv2502/csa-automation/settings/secrets/actions`

| Secret Name | Value |
|-------------|-------|
| `NEXUS_USERNAME` | `cicd-user` |
| `NEXUS_PASSWORD` | `CiCd-NexUs-2026` |
| `AWS_ACCESS_KEY_ID` | Your nextera-clone AWS access key |
| `AWS_SECRET_ACCESS_KEY` | Your nextera-clone AWS secret key |
| `AWS_REGION` | `us-east-1` |
| `EKS_CLUSTER_NAME` | `csa-clone-eks` |
| `K8S_NAMESPACE` | `csa-clone` |

---

## Step 8: Test Docker Login

From your local machine:

```bash
# Configure Docker for insecure registry
echo '{"insecure-registries": ["<PUBLIC_IP>:8083"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

# Login to Nexus
docker login <PUBLIC_IP>:8083 \
  --username cicd-user \
  --password CiCd-NexUs-2026

# Test push
docker pull nginx:latest
docker tag nginx:latest <PUBLIC_IP>:8083/csa/test:1.0.0
docker push <PUBLIC_IP>:8083/csa/test:1.0.0
```

Expected output: `Login Succeeded`

---

## Step 9: Configure Kubernetes for Nexus Registry

### 9.1 Configure Nodes for Insecure HTTP Registry

Apply containerd configuration to all EKS nodes:

```bash
# Apply DaemonSet
kubectl apply -f k8s/containerd-config-daemonset.yaml

# Verify DaemonSet
kubectl get daemonset -n kube-system containerd-config

# Check logs
kubectl logs -n kube-system -l app=containerd-config
```

This configures all EKS nodes to pull from the insecure HTTP registry.

### 9.2 Create ImagePullSecret (Required if Anonymous Access Disabled)

If you disabled anonymous access in Nexus (recommended for production), create the ImagePullSecret:

```bash
# Run the script to create the secret
./k8s/create-nexus-secret.sh
```

**What this does:**
- Creates a Kubernetes secret named `nexus-registry-secret` in the `csa-clone` namespace
- Contains Nexus credentials (cicd-user / CiCd-NexUs-2026)
- Allows Kubernetes to authenticate when pulling images

**Verify the secret:**
```bash
kubectl get secret nexus-registry-secret -n csa-clone
kubectl describe secret nexus-registry-secret -n csa-clone
```

**Note:** All Helm charts are already configured to use this secret:
```yaml
imagePullSecrets:
  - name: nexus-registry-secret
```

---

## Nexus Configuration Summary

| Component | Value |
|-----------|-------|
| EC2 Instance Type | t3.small (2GB RAM) |
| Nexus URL | `http://<PUBLIC_IP>:8081` |
| Admin Username | `admin` |
| Admin Password | `CstgQa-123` |
| CI/CD Username | `cicd-user` |
| CI/CD Password | `CiCd-NexUs-2026` |
| Docker Hosted Registry | `<PUBLIC_IP>:8083` |
| Docker Proxy Registry | `<PUBLIC_IP>:8082` (optional) |
| Docker Group Registry | `<PUBLIC_IP>:8084` (optional) |

---

## Troubleshooting

### GitHub Actions: 401 Unauthorized Error

**Symptom:**
```
Error response from daemon: login attempt to http://44.202.63.187:8083/v2/
failed with status: 401 Unauthorized
```

**Root Cause:** The `cicd-user` does not exist in Nexus or has incorrect credentials.

**Diagnosis:**

1. **Check if cicd-user exists:**
```bash
ssh -i ./nextera-clone-nexus-key.pem ec2-user@44.202.63.187 \
  "curl -u admin:CstgQa-123 http://localhost:8081/service/rest/v1/security/users | \
  jq '.[] | select(.userId==\"cicd-user\")'"
```

If this returns nothing, the user was not created.

2. **List all users to confirm:**
```bash
ssh -i ./nextera-clone-nexus-key.pem ec2-user@44.202.63.187 \
  "curl -u admin:CstgQa-123 http://localhost:8081/service/rest/v1/security/users | \
  jq '.[] | {userId, firstName, lastName, roles}'"
```

**Fix:**

1. **Create cicd-user via API:**
```bash
ssh -i ./nextera-clone-nexus-key.pem ec2-user@44.202.63.187 'curl -X POST \
  "http://localhost:8081/service/rest/v1/security/users" \
  -u "admin:CstgQa-123" \
  -H "Content-Type: application/json" \
  -d "{
    \"userId\": \"cicd-user\",
    \"firstName\": \"CI\",
    \"lastName\": \"CD User\",
    \"emailAddress\": \"cicd@localhost\",
    \"password\": \"CiCd-NexUs-2026\",
    \"status\": \"active\",
    \"roles\": [\"nx-admin\"]
  }"'
```

2. **Test credentials:**
```bash
curl -u "cicd-user:CiCd-NexUs-2026" http://44.202.63.187:8083/v2/
# Should return empty response (exit code 0)
```

3. **Update GitHub Secrets:**
```bash
echo "cicd-user" | gh secret set NEXUS_USERNAME
echo "CiCd-NexUs-2026" | gh secret set NEXUS_PASSWORD

# Verify secrets were updated
gh secret list | grep NEXUS
```

4. **Trigger workflow again:**
```bash
gh workflow run "Deploy to EKS" --ref main
```

### Nexus Container Won't Start

```bash
# Check container logs
docker logs nexus

# If memory error, verify t3.small instance (not t3.micro)
# Restart container
docker restart nexus
```

### Cannot Access Nexus UI

```bash
# Check security group allows port 8081
aws ec2 describe-security-groups \
  --profile nextera-clone \
  --region us-east-1 \
  --group-ids $SG_ID

# Check Nexus is listening
docker exec nexus netstat -tuln | grep 8081
```

### Docker Push Fails

```bash
# Ensure Docker daemon configured for insecure registry
cat /etc/docker/daemon.json

# Should contain:
# {"insecure-registries": ["<PUBLIC_IP>:8083"]}
```

### Kubernetes Pods Can't Pull Images

```bash
# Verify containerd config on nodes
kubectl debug node/<node-name> -it --image=busybox
cat /host/etc/containerd/config.toml | grep -A 5 "<PUBLIC_IP>"
```

---

## Next Steps

1. ✅ Complete Nexus setup using this guide
2. ✅ Configure GitHub secrets
3. ✅ Apply containerd configuration to EKS nodes
4. ✅ Trigger GitHub Actions workflow to build and push images
5. ✅ Deploy application pods using Helm charts

---

## Reference

- **Nexus Documentation:** https://help.sonatype.com/repomanager3
- **Docker Registry Setup:** https://help.sonatype.com/repomanager3/nexus-repository-administration/formats/docker-registry
