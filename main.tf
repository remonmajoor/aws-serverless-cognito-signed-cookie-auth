terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
  profile = var.profile
}

# CloudFront requires the certificate in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  profile = var.profile
}