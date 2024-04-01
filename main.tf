terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "assume_role"
  region = "us-east-1"
}

# Create admin iam policy document
data "aws_iam_policy_document" "admin_policy_doc" {
  statement {
    sid     = "1"
    actions = ["s3:GetObject", "s3:GetObjectTagging", "s3:ListObject"]
    resources = [
      "arn:aws:s3:::*",
      "arn:aws:s3:::terraform-cpt/*",
      "arn:aws:s3:::terraform-cpt/lambda_function_jsr.zip"
    ]
  }
  statement {
    sid       = "2"
    actions   = ["s3:CreateBucket"]
    resources = ["*"]
  }

  statement {
    sid       = "3"
    actions   = ["dynamodb:*"]
    resources = ["*"]
  }

  statement {
    sid       = "4"
    actions   = ["comprehend:*"]
    resources = ["*"]
  }

  statement {
    sid       = "5"
    actions   = ["lambda:*"]
    resources = ["*"]
  }
}

# Create Admin iam policy
resource "aws_iam_policy" "admin_iam_policy" {
  name   = "admin-policy"
  policy = data.aws_iam_policy_document.admin_policy_doc.json
  path   = "/"
}

## Create Admin role
resource "aws_iam_role" "admin" {
  name = "admin"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "*"
        }
      }
    ]
  })
}


# Assume role configuration
data "aws_iam_policy_document" "assume_role_policy_doc" {
  statement {
    actions   = ["sts:AssumeRole"]
    resources = [resource.aws_iam_role.admin.arn]
  }
}

resource "aws_iam_policy" "assume_role_policy" {
  name   = "assume-role-policy"
  policy = data.aws_iam_policy_document.assume_role_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "assume_role_attachment" {
  role       = resource.aws_iam_role.admin.name
  policy_arn = resource.aws_iam_policy.assume_role_policy.arn
  provider   = aws.assume_role
}

# assume role via sts provider
provider "aws" {
  alias  = "sts"
  region = "us-east-1"
  assume_role {
    role_arn = resource.aws_iam_role.admin.arn
  }
}

## DynamoDB
resource "aws_dynamodb_table" "game_expectations" {
  name         = "game_expectations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "game"
  range_key    = "opinion"

  attribute {
    name = "game"
    type = "S"
  }

  attribute {
    name = "opinion"
    type = "S"
  }

  attribute {
    name = "sentiment"
    type = "S"
  }

  # Define Global Secondary Index for the "sentiment" attribute
  global_secondary_index {
    name            = "SentimentIndex"
    hash_key        = "sentiment"
    projection_type = "ALL" # Adjust based on your needs
    read_capacity   = 5     # Adjust based on your needs
    write_capacity  = 5     # Adjust based on your needs
  }
}

# Lambda deployment package from public S3
data "aws_s3_object" "lambda_deployment_package" {
  bucket = "terraform-cpt"
  key    = "lambda_function_jsr.zip"
}

# 
resource "aws_lambda_function" "extract_sentiment" {
  function_name = "extract_sentiment"
  handler       = "extract_sentiment.lambda_handler"
  runtime       = "python3.8"
  role          = resource.aws_iam_role.admin.arn
  timeout       = 60
  memory_size   = 512
  s3_bucket     = "terraform-cpt"
  s3_key        = "lambda_function_jsr.zip"
  environment {
    variables = {
      DYNAMODB_TABLE = "${resource.aws_dynamodb_table.game_expectations.name}"
    }
  }
}
