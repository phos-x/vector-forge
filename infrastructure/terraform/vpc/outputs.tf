output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "nat_gateway_ips" {
  description = "List of Elastic IPs attached to NAT Gateways"
  value       = module.vpc.nat_public_ips
}

output "vpc_endpoints" {
  description = "Map of VPC endpoint IDs"
  value = {
    s3       = module.vpc_endpoints.endpoints["s3"].id
    dynamodb = module.vpc_endpoints.endpoints["dynamodb"].id
    sqs      = module.vpc_endpoints.endpoints["sqs"].id
  }
}
