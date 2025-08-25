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