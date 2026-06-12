# Architecture Overview

## System Design

Vector Forge implements a RAG (Retrieval-Augmented Generation) system with a focus on platform engineering best practices. The architecture is designed to demonstrate real-world patterns while maintaining simplicity through strategic mocking.

## Core Principles

### 1. Clear Layer Separation
The system is organized into distinct layers with well-defined interfaces:

```
┌─────────────────────────────────────────────────────┐
│                    API Gateway                       │
└───────────────┬─────────────────────┬───────────────┘
                │                     │
        ┌───────▼───────┐     ┌──────▼──────┐
        │ Query Service │     │  Ingestion  │
        │               │     │   Service   │
        └───────┬───────┘     └──────┬──────┘
                │                     │
        ┌───────▼───────┐     ┌──────▼──────┐
        │  Vector DB    │     │     SQS     │
        │  (DynamoDB +  │     │   Queue     │
        │   S3 Index)   │     │             │
        └───────┬───────┘     └──────┬──────┘
                │                     │
        ┌───────▼─────────────────────▼──────┐
        │         Mock Boundaries              │
        │  • LLM API (OpenAI-compatible)      │
        │  • Document Corpus (S3 simulator)   │
        └─────────────────────────────────────┘
```

### 2. Two Real Data Paths

#### Query Path
1. **Request Receipt**: API Gateway receives query
2. **Vector Search**: Query Service transforms query → vectors
3. **Retrieval**: Fetch relevant documents from vector store
4. **Context Assembly**: Combine query + retrieved docs
5. **LLM Call**: Send to mock LLM endpoint
6. **Response**: Return generated response

#### Ingestion Path
1. **Document Upload**: New document arrives via API
2. **Queue**: Message pushed to SQS
3. **Processing**: Ingestion Service picks up job
4. **Chunking**: Document split into semantic chunks
5. **Embedding**: Chunks vectorized (mock embedding service)
6. **Storage**: Vectors stored in DynamoDB, docs in S3

### 3. Mocking Strategy

Only two boundaries are mocked:

**Mock 1: LLM Caller**
- OpenAI-compatible REST API
- Configurable responses for testing
- Latency simulation for realistic behavior
- Located: `services/mocks/llm-mock/`

**Mock 2: Document Corpus**
- S3-compatible object store (MinIO or LocalStack)
- Simulates production document storage
- Located: `services/mocks/corpus-mock/`

All other components (K8s, networking, queues, storage, observability) are real.

## Infrastructure Components

### AWS Resources (via Terraform)

**VPC (`infrastructure/terraform/vpc/`)**
- Public/private subnet architecture
- NAT gateways for private subnets
- VPC endpoints for AWS services

**EKS (`infrastructure/terraform/eks/`)**
- Managed Kubernetes control plane
- Node groups with autoscaling
- IRSA (IAM Roles for Service Accounts)
- KRO (Kubernetes Resource Orchestrator) installed

**Storage (`infrastructure/terraform/storage/`)**
- S3 buckets: documents, vectors, backups
- DynamoDB: vector metadata and indexes
- SQS: ingestion job queue

### Kubernetes Resources

**Namespaces**
- `vector-forge`: Main application services
- `observability`: Prometheus, Grafana
- `security`: Policy engines

**Services**
- Query Service (Go/Python)
- Ingestion Service (Python)
- LLM Mock (Python/FastAPI)
- Corpus Mock (MinIO)

### Observability Stack

**Metrics**
- Prometheus for metrics collection
- Service-level indicators (SLIs):
  - Query latency (p50, p95, p99)
  - Ingestion throughput
  - Vector store latency
  - Mock service availability

**Dashboards**
- Grafana with pre-built dashboards:
  - System overview
  - Query path performance
  - Ingestion pipeline health
  - Resource utilization

**Logging**
- CloudWatch Logs for application logs
- Structured JSON logging
- Correlation IDs for tracing

### Security & Policy

**Policy Enforcement**
- OPA (Open Policy Agent) or Kyverno
- Policies in `security/policies/`:
  - Required labels
  - Resource limits
  - Network policies
  - Image scanning enforcement

**RBAC**
- Namespace-scoped roles
- Service account permissions
- AWS IAM integration via IRSA

## Kubernetes Resource Orchestrator (KRO)

KRO is used to define higher-level platform abstractions instead of manual environment assembly.

Example KRO ResourceGroup:
```yaml
apiVersion: kro.run/v1alpha1
kind: ResourceGroup
metadata:
  name: rag-service
spec:
  resources:
  - service: { ... }
  - deployment: { ... }
  - hpa: { ... }
  - networkpolicy: { ... }
```

## Technology Choices

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Container Orchestration | Kubernetes (EKS) | Industry standard, rich ecosystem |
| IaC | Terraform | AWS native, mature tooling |
| Vector Store | DynamoDB + S3 | Serverless, scalable, cost-effective |
| Queue | SQS | Managed, reliable, AWS native |
| Observability | Prometheus + Grafana | CNCF standard, self-hosted |
| Policy | OPA/Kyverno | CNCF, declarative, GitOps-friendly |
| Platform Abstraction | KRO | Kubernetes-native, reduces boilerplate |

## Deployment Topology

**Development**
- Single-node EKS cluster
- Reduced resource limits
- Mock services in-cluster

**Production**
- Multi-AZ EKS cluster
- Autoscaling enabled
- Separate VPC for isolation

## Future Enhancements

- [ ] Replace mocks with real LLM provider integration
- [ ] Add vector database (Pinecone, Weaviate, or pgvector)
- [ ] Implement A/B testing framework
- [ ] Add distributed tracing (Tempo/Jaeger)
- [ ] Multi-region deployment support
