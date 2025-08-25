output "bucket_name" {
  value       = aws_s3_bucket.site.bucket
  description = "Name of the S3 bucket used as the CloudFront origin"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.cloudfront_distribution.id
  description = "CloudFront distribution ID"
}

output "acm_certificate_arn" {
  value       = aws_acm_certificate_validation.cert.certificate_arn
  description = "Issued ACM certificate ARN in us-east-1"
}

output "public_key_pem" {
  value       = tls_private_key.cookie_signing.public_key_pem
  description = "Public key you can publish/use in your authorizer."
}

output "kid" {
  value       = random_uuid.kid.result
  description = "Key ID embedded in the secret (helpful for rotation)."
}