data "archive_file" "cookie_issuer" {
  type        = "zip"
  source_file = "./dist/lambda/cookie_issuer.js"
  output_path = "./dist/lambda/function.zip"
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
  function_name    = "cookie_issuer_function"
  role             = aws_iam_role.cookie_issuer.arn
  handler          = "cookie_issuer.handler"
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