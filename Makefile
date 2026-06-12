# Vector Forge Makefile

.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

##@ Infrastructure

.PHONY: tf-init-vpc
tf-init-vpc: ## Initialize Terraform for VPC
	cd infrastructure/terraform/vpc && terraform init

.PHONY: tf-plan-vpc
tf-plan-vpc: ## Plan Terraform for VPC
	cd infrastructure/terraform/vpc && terraform plan -var-file=../environments/dev.tfvars

.PHONY: tf-apply-vpc
tf-apply-vpc: ## Apply Terraform for VPC
	cd infrastructure/terraform/vpc && terraform apply -var-file=../environments/dev.tfvars

.PHONY: tf-init-eks
tf-init-eks: ## Initialize Terraform for EKS
	cd infrastructure/terraform/eks && terraform init

.PHONY: tf-apply-eks
tf-apply-eks: ## Apply Terraform for EKS
	cd infrastructure/terraform/eks && terraform apply -var-file=../environments/dev.tfvars

.PHONY: tf-init-storage
tf-init-storage: ## Initialize Terraform for Storage
	cd infrastructure/terraform/storage && terraform init

.PHONY: tf-apply-storage
tf-apply-storage: ## Apply Terraform for Storage
	cd infrastructure/terraform/storage && terraform apply -var-file=../environments/dev.tfvars

.PHONY: infra-up
infra-up: tf-apply-vpc tf-apply-eks tf-apply-storage ## Deploy all infrastructure

##@ Services

.PHONY: build-query
build-query: ## Build query service Docker image
	cd services/query-service && docker build -t vector-forge-query:latest .

.PHONY: build-ingestion
build-ingestion: ## Build ingestion service Docker image
	cd services/ingestion-service && docker build -t vector-forge-ingestion:latest .

.PHONY: build-llm-mock
build-llm-mock: ## Build LLM mock service Docker image
	cd services/mocks/llm-mock && docker build -t vector-forge-llm-mock:latest .

.PHONY: build-all
build-all: build-query build-ingestion build-llm-mock ## Build all Docker images

##@ Kubernetes

.PHONY: k8s-deploy-dev
k8s-deploy-dev: ## Deploy to dev environment
	kubectl apply -k k8s/overlays/dev

.PHONY: k8s-deploy-prod
k8s-deploy-prod: ## Deploy to prod environment
	kubectl apply -k k8s/overlays/prod

.PHONY: k8s-status
k8s-status: ## Check Kubernetes deployment status
	kubectl get pods -n vector-forge
	kubectl get svc -n vector-forge

.PHONY: k8s-logs-query
k8s-logs-query: ## Tail query service logs
	kubectl logs -n vector-forge -l app=query-service -f

.PHONY: k8s-logs-ingestion
k8s-logs-ingestion: ## Tail ingestion service logs
	kubectl logs -n vector-forge -l app=ingestion-service -f

##@ Development

.PHONY: lint
lint: ## Run linting
	flake8 services/query-service/src
	flake8 services/ingestion-service/src

.PHONY: format
format: ## Format code
	black services/query-service/src
	black services/ingestion-service/src

.PHONY: test
test: ## Run tests
	@echo "Tests not yet implemented"

##@ Cleanup

.PHONY: clean-k8s
clean-k8s: ## Remove Kubernetes resources
	kubectl delete namespace vector-forge

.PHONY: clean-infra
clean-infra: ## Destroy all infrastructure (CAUTION!)
	cd infrastructure/terraform/storage && terraform destroy -var-file=../environments/dev.tfvars
	cd infrastructure/terraform/eks && terraform destroy -var-file=../environments/dev.tfvars
	cd infrastructure/terraform/vpc && terraform destroy -var-file=../environments/dev.tfvars
