terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.27"
      configuration_aliases = [aws.us_east_1]
    }
    awscc = {
      source                = "hashicorp/awscc"
      version               = "~> 1.84"
      configuration_aliases = [awscc.us_east_1]
    }
  }
}
