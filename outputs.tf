output "bucket_name" {
  value       = aws_s3_bucket.site.bucket
  description = "Name of the S3 bucket used as the CloudFront origin"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.this.domain_name
  description = "CloudFront distribution domain name"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.this.id
  description = "CloudFront distribution ID"
}

output "acm_certificate_arn" {
  value       = aws_acm_certificate_validation.cert.certificate_arn
  description = "Issued ACM certificate ARN in us-east-1"
}
