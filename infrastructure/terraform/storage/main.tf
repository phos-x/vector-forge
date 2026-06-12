terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

data "terraform_remote_state" "eks" {
  backend = "local"
  
  config = {
    path = "../eks/terraform.tfstate"
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.cluster_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
}

################################################################################
# S3 Buckets
################################################################################

# Documents bucket
resource "aws_s3_bucket" "documents" {
  bucket = "${local.name_prefix}-documents"
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  
  versioning_configuration {
    status = var.environment == "prod" ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Vectors bucket
resource "aws_s3_bucket" "vectors" {
  bucket = "${local.name_prefix}-vectors"
}

resource "aws_s3_bucket_versioning" "vectors" {
  bucket = aws_s3_bucket.vectors.id
  
  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vectors" {
  bucket = aws_s3_bucket.vectors.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vectors" {
  bucket = aws_s3_bucket.vectors.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle for vectors bucket (optional cleanup)
resource "aws_s3_bucket_lifecycle_configuration" "vectors" {
  bucket = aws_s3_bucket.vectors.id
  
  rule {
    id     = "delete-old-vectors"
    status = var.environment == "dev" ? "Enabled" : "Disabled"
    
    expiration {
      days = 30
    }
  }
}

################################################################################
# DynamoDB Tables
################################################################################

# Vector metadata table
resource "aws_dynamodb_table" "vector_metadata" {
  name         = "${local.name_prefix}-vector-metadata"
  billing_mode = var.environment == "prod" ? "PAY_PER_REQUEST" : "PROVISIONED"
  
  read_capacity  = var.environment == "prod" ? null : 5
  write_capacity = var.environment == "prod" ? null : 5
  
  hash_key  = "document_id"
  range_key = "chunk_id"
  
  attribute {
    name = "document_id"
    type = "S"
  }
  
  attribute {
    name = "chunk_id"
    type = "S"
  }
  
  attribute {
    name = "created_at"
    type = "N"
  }
  
  global_secondary_index {
    name            = "created_at-index"
    hash_key        = "document_id"
    range_key       = "created_at"
    projection_type = "ALL"
    
    read_capacity  = var.environment == "prod" ? null : 5
    write_capacity = var.environment == "prod" ? null : 5
  }
  
  point_in_time_recovery {
    enabled = var.environment == "prod" ? true : false
  }
  
  server_side_encryption {
    enabled = true
  }
}

################################################################################
# SQS Queues
################################################################################

# Ingestion queue
resource "aws_sqs_queue" "ingestion" {
  name                       = "${local.name_prefix}-ingestion"
  delay_seconds              = 0
  max_message_size           = 262144  # 256 KB
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 20      # Long polling
  visibility_timeout_seconds = 300     # 5 minutes
  
  sqs_managed_sse_enabled = true
}

# Dead letter queue
resource "aws_sqs_queue" "ingestion_dlq" {
  name = "${local.name_prefix}-ingestion-dlq"
  
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

# Redrive policy
resource "aws_sqs_queue_redrive_policy" "ingestion" {
  queue_url = aws_sqs_queue.ingestion.id
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ingestion_dlq.arn
    maxReceiveCount     = 3
  })
}

################################################################################
# IAM Roles for Service Accounts (IRSA)
################################################################################

# Query service role
module "query_service_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"
  
  role_name = "${local.name_prefix}-query-service"
  
  role_policy_arns = {
    dynamodb = aws_iam_policy.query_service_dynamodb.arn
    s3       = aws_iam_policy.query_service_s3.arn
  }
  
  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.eks.outputs.oidc_provider_arn
      namespace_service_accounts = ["vector-forge:query-service"]
    }
  }
}

resource "aws_iam_policy" "query_service_dynamodb" {
  name        = "${local.name_prefix}-query-service-dynamodb"
  description = "DynamoDB access for query service"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem"
        ]
        Resource = [
          aws_dynamodb_table.vector_metadata.arn,
          "${aws_dynamodb_table.vector_metadata.arn}/index/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "query_service_s3" {
  name        = "${local.name_prefix}-query-service-s3"
  description = "S3 access for query service"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*",
          aws_s3_bucket.vectors.arn,
          "${aws_s3_bucket.vectors.arn}/*"
        ]
      }
    ]
  })
}

# Ingestion service role
module "ingestion_service_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"
  
  role_name = "${local.name_prefix}-ingestion-service"
  
  role_policy_arns = {
    dynamodb = aws_iam_policy.ingestion_service_dynamodb.arn
    s3       = aws_iam_policy.ingestion_service_s3.arn
    sqs      = aws_iam_policy.ingestion_service_sqs.arn
  }
  
  oidc_providers = {
    main = {
      provider_arn               = data.terraform_remote_state.eks.outputs.oidc_provider_arn
      namespace_service_accounts = ["vector-forge:ingestion-service"]
    }
  }
}

resource "aws_iam_policy" "ingestion_service_dynamodb" {
  name        = "${local.name_prefix}-ingestion-service-dynamodb"
  description = "DynamoDB access for ingestion service"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.vector_metadata.arn
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "ingestion_service_s3" {
  name        = "${local.name_prefix}-ingestion-service-s3"
  description = "S3 access for ingestion service"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*",
          aws_s3_bucket.vectors.arn,
          "${aws_s3_bucket.vectors.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "ingestion_service_sqs" {
  name        = "${local.name_prefix}-ingestion-service-sqs"
  description = "SQS access for ingestion service"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.ingestion.arn
        ]
      }
    ]
  })
}
