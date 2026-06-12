output "documents_bucket_name" {
  description = "Name of the S3 bucket for documents"
  value       = aws_s3_bucket.documents.id
}

output "vectors_bucket_name" {
  description = "Name of the S3 bucket for vectors"
  value       = aws_s3_bucket.vectors.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for vector metadata"
  value       = aws_dynamodb_table.vector_metadata.name
}

output "sqs_queue_url" {
  description = "URL of the SQS ingestion queue"
  value       = aws_sqs_queue.ingestion.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS ingestion queue"
  value       = aws_sqs_queue.ingestion.arn
}

output "query_service_role_arn" {
  description = "IAM role ARN for query service"
  value       = module.query_service_irsa.iam_role_arn
}

output "ingestion_service_role_arn" {
  description = "IAM role ARN for ingestion service"
  value       = module.ingestion_service_irsa.iam_role_arn
}
