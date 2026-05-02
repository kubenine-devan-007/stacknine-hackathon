output "vpc_id" {
  description = "VPC ID for subnets and security groups in later steps."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnets — ALB will attach here."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnets — ECS, RDS, Lambda."
  value       = module.vpc.private_subnets
}

output "nat_gateway_public_ips" {
  description = "NAT egress public IP(s) — one NAT for hackathon cost."
  value       = module.vpc.nat_public_ips
}

output "alb_dns_name" {
  description = "Open this URL in a browser (HTTP) for the web UI (task testing)."
  value       = "http://${aws_lb.main.dns_name}"
}

output "rds_address" {
  description = "PostgreSQL endpoint — use with manual psql init.sql (TASK-1)."
  value       = aws_db_instance.main.address
}

output "s3_uploads_bucket" {
  description = "Invoice PDF uploads bucket name."
  value       = aws_s3_bucket.uploads.bucket
}

output "ecr_repository_urls" {
  description = "docker push targets — tag :latest after build."
  value = {
    for k, v in aws_ecr_repository.service : k => v.repository_url
  }
}
