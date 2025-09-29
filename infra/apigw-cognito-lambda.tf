#### API GW #### 

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

#### Cognito User pool ####

resource "aws_cognito_user_pool" "user_pool" {
  name                 = "${var.project_name}-user-pool"
  mfa_configuration    = "OFF"
  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  name         = "${var.project_name}-app-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret                         = false
  prevent_user_existence_errors           = "ENABLED"
  supported_identity_providers            = ["COGNITO"]
  enable_token_revocation                 = true

  # Hosted UI / OAuth
  allowed_oauth_flows_user_pool_client    = true
  allowed_oauth_flows                     = ["code"]
  allowed_oauth_scopes                    = ["openid","email","profile"]
  callback_urls                           = var.callback_urls
  logout_urls                             = var.logout_urls

  # Direct auth (if you also hit Cognito SRP from your app)
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Token lifetimes (optional)
  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_pool_domain" "user_pool" {
  domain          = var.cognito_domain_name
  certificate_arn = aws_acm_certificate.cert.arn
  user_pool_id    = aws_cognito_user_pool.user_pool.id
  depends_on      = [aws_acm_certificate_validation.cert]
}

resource "aws_cognito_user" "user" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  username     = var.cognito_user_email

  attributes = {
    email          = var.cognito_user_email
    email_verified = true
    name           = var.cognito_user
  }

  temporary_password       = var.cognito_user_password
  desired_delivery_mediums = ["EMAIL"]
  force_alias_creation     = false
}

#### Lambda for cookie issuing ####

data "archive_file" "cookie_issuer" {
  type        = "zip"
  source_file = "../services/cookie-issuer/dist/cookie-issuer.js"
  output_path = "../services/cookie-issuer/dist/function.zip"
}

resource "aws_iam_role" "cookie_issuer" {
  name = "lambda-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cookie_issuer_logging" {
  role       = aws_iam_role.cookie_issuer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy document for allowing role to get private key from secrets manager # TO MODIFY
data "aws_iam_policy_document" "secrets_manager_get_secret" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.cookie_signing.arn]
  }
}



# Policy for allowing role to get private key from secrets manager # TO MODIFY
resource "aws_iam_policy" "secrets_manager_get_secret" {
  name   = "secrets-manager-get-secret"
  policy = data.aws_iam_policy_document.secrets_manager_get_secret.json
}

resource "aws_iam_role_policy_attachment" "attach_kms_sign" {
  role       = aws_iam_role.cookie_issuer.name
  policy_arn = aws_iam_policy.secrets_manager_get_secret.arn
}

  resource "aws_lambda_function" "cookie_issuer" {
    filename         = data.archive_file.cookie_issuer.output_path
    function_name    = "cookie-issuer-function"
    role             = aws_iam_role.cookie_issuer.arn
    handler          = "cookie-issuer.handler"
    source_code_hash = data.archive_file.cookie_issuer.output_base64sha256

    runtime = "nodejs22.x"

    environment {
      variables = {
        ENVIRONMENT       = "production"
        LOG_LEVEL         = "info"
        PRIVATE_KEY_ARN   = aws_secretsmanager_secret.cookie_signing.arn
        COG_USER_POOL_ID  = aws_cognito_user_pool.user_pool.id
        COG_APP_CLIENT_ID = aws_cognito_user_pool_client.app_client.id
        CF_RESOURCE       = var.cloudfront_restricted_path
        CF_COOKIE_DOMAIN  = var.cloudfront_domain_name
        CF_KEY_PAIR_ID     = aws_cloudfront_public_key.cookie_signing.id
      }
    }
  }

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cookie_issuer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.http.id}/$default/POST/api/auth"
}

resource "random_uuid" "kid" {}

resource "tls_private_key" "cookie_signing" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}

# Use secrets manager to store private/public key pair for signing cookies
resource "aws_secretsmanager_secret" "cookie_signing" {
  name                    = "cookie_signing"
  description             = "RSA private key for cookie signing (includes public key)."
  recovery_window_in_days = 7
  lifecycle { prevent_destroy = false }
}

# Store both private & public PEM in JSON. jsonencode handles newlines safely.
resource "aws_secretsmanager_secret_version" "cookie_key_current" {
  secret_id     = aws_secretsmanager_secret.cookie_signing.id
  secret_string = jsonencode({
    kid           = random_uuid.kid.result
    kty           = "RSA"
    alg           = "RS256"
    use           = "sig"
    privateKeyPem = tls_private_key.cookie_signing.private_key_pem
    publicKeyPem  = tls_private_key.cookie_signing.public_key_pem
  })
}