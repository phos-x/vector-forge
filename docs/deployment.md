# Deployment Guide

## Prerequisites

### Required Tools
- AWS CLI (v2.x)
- Terraform (>= 1.5.0)
- kubectl (>= 1.27)
- helm (>= 3.12)
- docker (>= 24.0)

### AWS Account Setup
1. AWS account with administrative access
2. Configured AWS credentials: `aws configure`
3. S3 bucket for Terraform state (optional but recommended)

## Initial Setup

### 1. Clone Repository
```bash
git clone https://github.com/phos-x/vector-forge.git
cd vector-forge
```

### 2. Configure Environment
```bash
# Copy example env file
cp .env.example .env

# Edit with your values
vim .env
```

Required environment variables:
```bash
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
CLUSTER_NAME=vector-forge
ENVIRONMENT=dev
```

## Infrastructure Deployment

### Step 1: VPC and Networking
```bash
cd infrastructure/terraform/vpc

# Initialize Terraform
terraform init

# Review plan
terraform plan -var-file=../environments/dev.tfvars

# Apply
terraform apply -var-file=../environments/dev.tfvars
```

**Resources Created:**
- VPC with public/private subnets
- NAT Gateways
- Internet Gateway
- Route tables
- VPC endpoints (S3, DynamoDB)

### Step 2: EKS Cluster
```bash
cd ../eks

terraform init
terraform plan -var-file=../environments/dev.tfvars
terraform apply -var-file=../environments/dev.tfvars
```

**Resources Created:**
- EKS cluster
- Node groups with autoscaling
- IAM roles and policies
- Security groups
- KRO (Kubernetes Resource Orchestrator)

**Configure kubectl:**
```bash
aws eks update-kubeconfig --name vector-forge --region us-east-1
kubectl get nodes
```

### Step 3: Storage and Queues
```bash
cd ../storage

terraform init
terraform plan -var-file=../environments/dev.tfvars
terraform apply -var-file=../environments/dev.tfvars
```

**Resources Created:**
- S3 buckets (documents, vectors, backups)
- DynamoDB tables (vector metadata)
- SQS queues (ingestion pipeline)
- IAM service account roles

## Application Deployment

### Step 1: Install Base Components
```bash
cd ../../../k8s

# Create namespace
kubectl create namespace vector-forge

# Apply base resources
kubectl apply -k base/
```

### Step 2: Deploy Observability Stack
```bash
# Install Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --create-namespace \
  --values ../observability/prometheus/values.yaml

# Install Grafana dashboards
kubectl apply -f ../observability/grafana/dashboards/
```

### Step 3: Deploy Security Policies
```bash
# Install OPA Gatekeeper or Kyverno
kubectl apply -f https://raw.githubusercontent.com/kyverno/kyverno/main/config/install.yaml

# Apply policies
kubectl apply -f ../security/policies/
```

### Step 4: Deploy Services

**Development Environment:**
```bash
kubectl apply -k overlays/dev/
```

**Production Environment:**
```bash
kubectl apply -k overlays/prod/
```

### Step 5: Verify Deployment
```bash
# Check all pods are running
kubectl get pods -n vector-forge

# Check services
kubectl get svc -n vector-forge

# View logs
kubectl logs -n vector-forge -l app=query-service --tail=50
```

## Service Configuration

### Query Service
Located: `services/query-service/`

Environment variables:
```yaml
VECTOR_STORE_ENDPOINT: dynamodb.us-east-1.amazonaws.com
S3_BUCKET: vector-forge-documents
LLM_ENDPOINT: http://llm-mock:8080
MAX_RESULTS: 5
```

### Ingestion Service
Located: `services/ingestion-service/`

Environment variables:
```yaml
SQS_QUEUE_URL: https://sqs.us-east-1.amazonaws.com/123/vector-forge
S3_BUCKET: vector-forge-documents
DYNAMODB_TABLE: vector-metadata
CHUNK_SIZE: 512
```

### Mock Services

**LLM Mock:**
```bash
# Expose locally for testing
kubectl port-forward -n vector-forge svc/llm-mock 8080:8080

# Test
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "test"}]}'
```

**Corpus Mock (MinIO):**
```bash
kubectl port-forward -n vector-forge svc/corpus-mock 9000:9000

# Access UI at http://localhost:9000
```

## Accessing Services

### API Gateway
```bash
# Get Load Balancer URL
kubectl get svc -n vector-forge vector-forge-gateway

# Test query endpoint
curl https://<LB-URL>/api/v1/query \
  -H "Content-Type: application/json" \
  -d '{"query": "What is vector forge?"}'
```

### Grafana Dashboard
```bash
# Port forward
kubectl port-forward -n observability svc/prometheus-grafana 3000:80

# Access at http://localhost:3000
# Default: admin / prom-operator
```

### Prometheus
```bash
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
```

## Monitoring and Troubleshooting

### Check Service Health
```bash
# Query service health
kubectl exec -n vector-forge deploy/query-service -- curl localhost:8080/health

# Ingestion service health
kubectl exec -n vector-forge deploy/ingestion-service -- curl localhost:8081/health
```

### View Metrics
```bash
# Query service metrics
kubectl exec -n vector-forge deploy/query-service -- curl localhost:8080/metrics

# Check SQS queue depth
aws sqs get-queue-attributes \
  --queue-url <QUEUE-URL> \
  --attribute-names ApproximateNumberOfMessages
```

### Common Issues

**Pods not starting:**
```bash
kubectl describe pod -n vector-forge <pod-name>
kubectl logs -n vector-forge <pod-name>
```

**AWS permissions issues:**
- Verify IRSA annotations on service accounts
- Check IAM role trust policies
- Review CloudWatch logs for AWS API errors

**Network connectivity:**
```bash
# Test from within cluster
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- /bin/bash
nslookup llm-mock.vector-forge.svc.cluster.local
```

## Scaling

### Manual Scaling
```bash
# Scale query service
kubectl scale deployment -n vector-forge query-service --replicas=5

# Scale ingestion service
kubectl scale deployment -n vector-forge ingestion-service --replicas=3
```

### Autoscaling (HPA)
Horizontal Pod Autoscalers are configured in the overlays:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: query-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: query-service
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Cleanup

### Remove Application
```bash
kubectl delete namespace vector-forge
kubectl delete namespace observability
```

### Destroy Infrastructure
```bash
cd infrastructure/terraform/storage
terraform destroy -var-file=../environments/dev.tfvars

cd ../eks
terraform destroy -var-file=../environments/dev.tfvars

cd ../vpc
terraform destroy -var-file=../environments/dev.tfvars
```

## CI/CD Integration

GitHub Actions workflows are provided in `.github/workflows/`:
- `build.yml`: Build and test services
- `deploy-dev.yml`: Deploy to dev environment
- `deploy-prod.yml`: Deploy to prod (manual approval)

Configure GitHub secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `EKS_CLUSTER_NAME`
