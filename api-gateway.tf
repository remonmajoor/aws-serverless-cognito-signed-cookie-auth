############################
# HTTP API
############################
resource "aws_apigatewayv2_api" "http" {
  name          = "ocr-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins     = var.allowed_origins
    allow_methods     = ["POST", "OPTIONS"]
    allow_headers     = ["authorization", "content-type", "cookie"]
    allow_credentials = true
    max_age           = 86400
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.http_api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId",
      routeKey       = "$context.routeKey",
      status         = "$context.status",
      integration    = "$context.integrationErrorMessage",
      sourceIp       = "$context.identity.sourceIp",
      userAgent      = "$context.identity.userAgent",
      requestTime    = "$context.requestTime",
      path           = "$context.path",
      protocol       = "$context.protocol"
    })
  }
}

############################
# Authorizers
############################
# 1) Cognito JWT (for /auth/cookie)
resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  name             = "cognito-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.user_pool.id}"
    audience = [aws_cognito_user_pool_client.app_client.id]
  }
}

############################
# Integrations
############################
resource "aws_apigatewayv2_integration" "issue_cookie" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.cookie_issuer.arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

############################
# Routes
############################
# Route 1: Accept Cognito JWT and SET the signed cookie
resource "aws_apigatewayv2_route" "auth_cookie" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "POST /api/auth"
  target             = "integrations/${aws_apigatewayv2_integration.issue_cookie.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}