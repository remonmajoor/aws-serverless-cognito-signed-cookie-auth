resource "aws_cloudwatch_log_group" "cookie_issuer" {
  name              = "/aws/lambda/${aws_lambda_function.cookie_issuer.function_name}"
  retention_in_days = 3
}

resource "aws_cloudwatch_log_group" "http_api_access" {
  name              = "/aws/apigw/${var.project_name}-httpapi"
  retention_in_days = 3
}