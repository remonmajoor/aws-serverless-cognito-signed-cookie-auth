variable "aws_region" {
  description = "AWS region for S3/Route53 API calls (CloudFront is global)."
  type        = string
}

variable "project_name" {
  description = "Short name used for tagging and resource naming."
  type        = string
}

variable "profile" {
  description = "Profile used by Terraform to have access to AWS"
  type        = string
}

variable "domain_name" {
  description = "FQDN to serve via CloudFront, e.g., cdn.example.com"
  type        = string
}

variable "cloudfront_domain_name" {
  description = "cheers mate"
  type        = string
}

variable "cognito_domain_name" {
  description = "FQDN to serve Cognito"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 Hosted Zone ID that contains the domain (e.g., Z123456...)."
  type        = string
}

variable "bucket_force_destroy" {
  description = "If true, allows Terraform to delete the bucket even if it contains objects."
  type        = bool
  default     = true
}

variable "price_class" {
  description = "CloudFront price class. One of PriceClass_100, PriceClass_200, PriceClass_All."
  type        = string
  default     = "PriceClass_100"
}

variable "default_root_object" {
  description = "Default root object served by CloudFront (should exist in the bucket)."
  type        = string
  default     = "index.html"
}

variable "tags" {
  description = "Tags to apply to supported resources."
  type        = map(string)
  default     = {}
}

variable "rsa_bits" {
  description = "Key pair for signing cookies."
  type = number
  default = 2048
}

variable "cloudfront_restricted_path" {
  description = "Restricted path by Cloudfront"
  type = string
  default = "/restricted/*"
}

variable "allowed_origins" {
  description = "Restricted path by Cloudfront"
  type = list(string)
}

variable "callback_urls" {
  description = "Restricted path by Cloudfront"
  type = list(string)
}

variable "logout_urls" {
  description = "value"
  type = list(string)
}

variable "cognito_user" {
  description = "Creation of a user in the cognito pool"
  type = string
}

variable "cognito_user_email" {
  description = "Creation of a user in the cognito pool"
  type = string
}

variable "cognito_user_password" {
  description = "Creation of a user in the cognito pool"
  type = string
}