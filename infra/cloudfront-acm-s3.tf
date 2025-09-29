#### Cloudfront ####

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for S3 origin ${aws_s3_bucket.site.bucket}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_public_key" "cookie_signing" {
  name        = "cookie-signing-pubkey"
  comment     = "Public key for signed cookies"
  encoded_key = tls_private_key.cookie_signing.public_key_pem
}

resource "aws_cloudfront_key_group" "trusted" {
  name    = "trusted-cookie-signers"
  items   = [aws_cloudfront_public_key.cookie_signing.id]
  comment = "Key group used for signed cookies"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

# If you already have these resources, reference them; otherwise set vars:
#   var.api_id (apigw v2 api id) and var.api_stage ("prod" by default)

resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} static content via OAC"
  aliases             = [var.cloudfront_domain_name]
  price_class         = var.price_class
  default_root_object = var.default_root_object

  # --- Origin: S3 (site + /restricted/*) ---
  origin {
    origin_id                = "s3-origin"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # --- NEW Origin: API Gateway (for /api/*) ---
  # If you created API in this stack:
  # domain_name = "${aws_apigatewayv2_api.http_api.api_id}.execute-api.${data.aws_region.current.name}.amazonaws.com"
  # origin_path = "/${aws_apigatewayv2_stage.prod.name}"
  origin {
    origin_id   = "apigw-origin"
    domain_name = "${aws_apigatewayv2_api.http.id}.execute-api.${var.aws_region}.amazonaws.com"

    custom_origin_config {
        origin_protocol_policy = "https-only"
        http_port              = 80
        https_port             = 443
        origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # --- Default behavior: S3 site ---
  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]
    compress        = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  # --- Keep your restricted path on S3 with signed cookies ---
  ordered_cache_behavior {
    path_pattern           = var.cloudfront_restricted_path   # e.g. "/restricted/*"
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    #cache_policy_id  = data.aws_cloudfront_cache_policy.caching_optimized.id
    cache_policy_id           = data.aws_cloudfront_cache_policy.caching_disabled.id  #TO REMOVE WHEN DONE DEBUGGING

    # Enforce signed cookies for this path
    trusted_key_groups = [aws_cloudfront_key_group.trusted.id]
  }

  # --- NEW: Route /api/* to API Gateway (no cache, forward auth/cookies/qs) ---
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "apigw-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods  = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]

    cache_policy_id           = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id  = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_acm_certificate_validation.cert]
}

#### ACM ####

resource "aws_acm_certificate" "cert" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }
  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.us_east_1 #us_east_1 is MANDATORY for ACM because CloudFront is a global service
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

#### S3 ####

data "aws_iam_policy_document" "site" {
  statement {
    sid = "AllowCloudFrontServicePrincipalReadOnly"
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cloudfront_distribution.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site.json
}

resource "aws_s3_bucket" "site" {
  bucket        = local.bucket_name
  force_destroy = var.bucket_force_destroy
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#### Route53 ####

# I am not creating the hosted zone with Terraform, you will need an already created hostzed zone and domain name server
resource "aws_route53_record" "cognito_cname" {
  zone_id = var.hosted_zone_id
  name    = var.cognito_domain_name
  type    = "CNAME"
  ttl     = 300
  records = [aws_cognito_user_pool_domain.user_pool.cloudfront_distribution]
}

resource "aws_route53_record" "cloudfront_cname" {
  zone_id = var.hosted_zone_id
  name    = var.cloudfront_domain_name
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.cloudfront_distribution.domain_name]
}