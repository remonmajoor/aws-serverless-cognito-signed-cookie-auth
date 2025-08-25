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