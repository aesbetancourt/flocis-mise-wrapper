# OpenTofu setup for the Floci lab. Every AWS call goes to the local emulator.
#
# The endpoint and the credentials are written here on purpose. Tofu then uses
# the emulator even when mise does not load the lab environment.
# Do not replace them with a named profile or environment variables.
#
# Endpoint list: floci-io/floci compatibility-tests/compat-terraform (2.1.0).

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Zips Lambda code with the archive_file data source. It makes no network calls.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # Keep state on disk. No lab state can reach a real S3 backend.
  backend "local" {
    path = "terraform.tfstate"
  }
}

locals {
  floci_endpoint = "http://localhost:4566"
}

provider "aws" {
  region = "us-east-1"

  # Dummy values. Floci maps a key that is not 12 digits to account 000000000000.
  access_key = "test"
  secret_key = "test"

  # Skip the checks that only real AWS can answer.
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  # A service without a line here sends its calls to real AWS, and they fail.
  # Add a line before you use a new service.
  endpoints {
    acm              = local.floci_endpoint
    apigateway       = local.floci_endpoint
    apigatewayv2     = local.floci_endpoint
    appautoscaling   = local.floci_endpoint
    appconfig        = local.floci_endpoint
    appsync          = local.floci_endpoint
    athena           = local.floci_endpoint
    backup           = local.floci_endpoint
    batch            = local.floci_endpoint
    cloudformation   = local.floci_endpoint
    cloudtrail       = local.floci_endpoint
    cloudwatch       = local.floci_endpoint
    codebuild        = local.floci_endpoint
    codedeploy       = local.floci_endpoint
    cognitoidp       = local.floci_endpoint
    cur              = local.floci_endpoint
    dynamodb         = local.floci_endpoint
    ec2              = local.floci_endpoint
    ecr              = local.floci_endpoint
    ecs              = local.floci_endpoint
    eks              = local.floci_endpoint
    elasticache      = local.floci_endpoint
    events           = local.floci_endpoint
    firehose         = local.floci_endpoint
    glue             = local.floci_endpoint
    guardduty        = local.floci_endpoint
    iam              = local.floci_endpoint
    kinesis          = local.floci_endpoint
    kms              = local.floci_endpoint
    lambda           = local.floci_endpoint
    logs             = local.floci_endpoint
    neptune          = local.floci_endpoint
    opensearch       = local.floci_endpoint
    pipes            = local.floci_endpoint
    rds              = local.floci_endpoint
    route53          = local.floci_endpoint
    s3               = local.floci_endpoint
    scheduler        = local.floci_endpoint
    secretsmanager   = local.floci_endpoint
    servicediscovery = local.floci_endpoint
    ses              = local.floci_endpoint
    sfn              = local.floci_endpoint
    sns              = local.floci_endpoint
    sqs              = local.floci_endpoint
    ssm              = local.floci_endpoint
    sts              = local.floci_endpoint
    transfer         = local.floci_endpoint
    wafv2            = local.floci_endpoint
  }
}
