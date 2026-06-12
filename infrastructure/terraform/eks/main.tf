terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "vector-forge"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "terraform_remote_state" "vpc" {
  backend = "local"
  
  config = {
    path = "../vpc/terraform.tfstate"
  }
}

data "aws_caller_identity" "current" {}

locals {
  cluster_name = "${var.cluster_name}-${var.environment}"
  
  node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = var.environment == "prod" ? ["t3.large"] : ["t3.medium"]
    capacity_type  = "ON_DEMAND"
  }
}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.16"
  
  cluster_name    = local.cluster_name
  cluster_version = "1.28"
  
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  
  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnets
  
  # Cluster security group rules
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }
  
  # Node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }
  
  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    default = {
      name = "${local.cluster_name}-node-group"
      
      use_name_prefix = true
      
      min_size     = var.environment == "prod" ? 3 : 1
      max_size     = var.environment == "prod" ? 10 : 5
      desired_size = var.environment == "prod" ? 3 : 2
      
      ami_type       = local.node_group_defaults.ami_type
      instance_types = local.node_group_defaults.instance_types
      capacity_type  = local.node_group_defaults.capacity_type
      
      disk_size = 50
      
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
      
      labels = {
        Environment = var.environment
        Workload    = "general"
      }
      
      tags = {
        Name = "${local.cluster_name}-node"
      }
    }
  }
  
  # Cluster access entry
  enable_cluster_creator_admin_permissions = true
  
  # Add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }
  
  tags = {
    Name = local.cluster_name
  }
}

################################################################################
# IRSA for EBS CSI Driver
################################################################################

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"
  
  role_name = "${local.cluster_name}-ebs-csi-driver"
  
  attach_ebs_csi_policy = true
  
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

################################################################################
# Install KRO (Kubernetes Resource Orchestrator)
################################################################################

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        var.aws_region
      ]
    }
  }
}

resource "helm_release" "kro" {
  name       = "kro"
  repository = "https://awslabs.github.io/kro"
  chart      = "kro"
  version    = "0.1.0"  # Pin version
  
  namespace        = "kro-system"
  create_namespace = true
  
  values = [
    yamlencode({
      replicaCount = var.environment == "prod" ? 2 : 1
    })
  ]
  
  depends_on = [module.eks]
}
