# Vector Forge

> A platform-engineering demo showcasing RAG (Retrieval-Augmented Generation) architecture with real AWS infrastructure and Kubernetes-native tooling.

## Overview

Vector Forge is a production-grade demonstration of platform engineering principles applied to a RAG system. It separates the system into clear layers while keeping the demo honest by mocking only two seams: the LLM caller and the document corpus.

## Architecture Principles

- **Clear Layer Separation**: Query and ingestion data paths are separated and independently scalable
- **Minimal Mocking**: Only LLM caller and document corpus are mocked; all other components are real
- **AWS Native**: Leverages VPC, EKS, S3, SQS, Lambda, DynamoDB, CloudWatch, and IAM
- **CNCF Aligned**: Uses CNCF-native projects for control, enforcement, and portability
- **Platform Abstractions**: Kubernetes Resource Orchestrator (KRO) for higher-level abstractions

## Key Components

### Data Paths
- **Query Service**: Handles vector search queries and response generation
- **Ingestion Service**: Processes documents, creates embeddings, and stores vectors

### Infrastructure
- **Terraform IaC**: Reproducible infrastructure across environments
- **EKS Cluster**: Kubernetes-managed compute layer
- **S3 + DynamoDB**: Storage for documents and vector metadata
- **SQS**: Async job processing for ingestion pipeline

### Observability & Security
- **Prometheus + Grafana**: Metrics and dashboards
- **Policy Enforcement**: OPA/Kyverno policies for compliance
- **RBAC**: Fine-grained access control

## Quick Start

```bash
# Clone the repository
git clone https://github.com/phos-x/vector-forge.git
cd vector-forge

# Set up infrastructure
cd infrastructure/terraform
terraform init
terraform plan
terraform apply

# Deploy services
cd ../../k8s
kubectl apply -k overlays/dev

# Check status
kubectl get pods -n vector-forge
```

## Project Structure

```
vector-forge/
├── docs/                     # Architecture and deployment docs
├── infrastructure/           # Terraform IaC and KRO definitions
├── services/                 # Application services (query, ingestion, mocks)
├── k8s/                      # Kubernetes manifests and Kustomize overlays
├── observability/            # Prometheus, Grafana configurations
├── security/                 # OPA policies and RBAC configs
└── scripts/                  # Automation and helper scripts
```

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Deployment Guide](docs/deployment.md)

## Guardrails

- ✅ Pinned versions for all providers, modules, and images
- ✅ Security, automation, policy, and observability as first-class deliverables
- ✅ CNCF-native projects wherever they strengthen control
- ✅ No manual environment assembly—use KRO for abstractions

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details
