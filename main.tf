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

# Create admin iam policy document
data "aws_iam_policy_document" "admin_policy_doc" {
  statement {
    sid     = "1"
    actions = ["s3:GetObject", "s3:GetObjectTagging", "s3:ListObject", "s3:*"]
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

  statement {
    actions   = ["sts:AssumeRole"]
    resources = [resource.aws_iam_role.admin.arn]
  }
}

## Create Admin role
resource "aws_iam_role" "admin" {
  name = "admin"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "*"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "admin_policy" {
  name   = "admin"
  path   = "/"
  policy = data.aws_iam_policy_document.admin_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = resource.aws_iam_role.admin.name
  policy_arn = resource.aws_iam_policy.admin_policy.arn
}

## DynamoDB
resource "aws_dynamodb_table" "game_expectations" {
  name         = "game_expectations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "Game"
  range_key    = "Sentiment"
  attribute {
    name = "Game"
    type = "S"
  }
  attribute {
    name = "Sentiment"
    type = "S"
  }
  attribute {
    name = "Positive"
    type = "N"
  }
  attribute {
    name = "Negative"
    type = "N"
  }
  attribute {
    name = "Neutral"
    type = "N"
  }
  attribute {
    name = "Description"
    type = "S"
  }
  attribute {
    name = "Genre"
    type = "S"
  }
  attribute {
    name = "Image"
    type = "S"
  }
  attribute {
    name = "Platforms"
    type = "S"
  }
  attribute {
    name = "ReleaseDate"
    type = "S"
  }
  global_secondary_index {
    name            = "PositiveIndex"
    hash_key        = "Positive"
    projection_type = "ALL" # Adjust based on your needs
    read_capacity   = 5     # Adjust based on your needs
    write_capacity  = 5     # Adjust based on your needs
  }
  global_secondary_index {
    name            = "NegativeIndex"
    hash_key        = "Negative"
    projection_type = "ALL" # Adjust based on your needs
    read_capacity   = 5     # Adjust based on your needs
    write_capacity  = 5     # Adjust based on your needs
  }
  global_secondary_index {
    name            = "NeutralIndex"
    hash_key        = "Neutral"
    projection_type = "ALL" # Adjust based on your needs
    read_capacity   = 5     # Adjust based on your needs
    write_capacity  = 5     # Adjust based on your needs
  }
  global_secondary_index {
    name            = "DescriptionIndex"
    hash_key        = "Description"
    projection_type = "ALL" # Adjust based on your needs
    read_capacity   = 5     # Adjust based on your needs
    write_capacity  = 5     # Adjust based on your needs
  }
  global_secondary_index {
    name            = "GenreIndex"
    hash_key        = "Genre"
    projection_type = "ALL" # Adjust based on your needs
    read_capacity   = 5     # Adjust based on your needs
    write_capacity  = 5     # Adjust based on your needs
  }
  global_secondary_index {
    name            = "ImageIndex"
    hash_key        = "Image"
    projection_type = "ALL" # Adjust based on your needs
    read_capacity   = 5     # Adjust based on your needs
    write_capacity  = 5     # Adjust based on your needs
  }
  global_secondary_index {
    name            = "PlatformsIndex"
    hash_key        = "Platforms"
    projection_type = "ALL" # Adjust based on your needs
    read_capacity   = 5     # Adjust based on your needs
    write_capacity  = 5     # Adjust based on your needs
  }
  global_secondary_index {
    name            = "ReleaseDateIndex"
    hash_key        = "ReleaseDate"
    projection_type = "ALL" # Adjust based on your needs
    read_capacity   = 5     # Adjust based on your needs
    write_capacity  = 5     # Adjust based on your needs
  }
}

# public bucket
resource "aws_s3_bucket" "terraform-cpt" {
  bucket = "terraform-cpt"
}

# Lambda deployment package from public S3
resource "aws_s3_object" "lambda_deployment_package" {
  bucket = "terraform-cpt"
  key    = "lambda_function_jsr.zip"
}

#
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.extract_sentiment.arn
  principal     = "s3.amazonaws.com"
  source_arn    = resource.aws_s3_bucket.terraform-cpt.arn
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

#
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = resource.aws_s3_bucket.terraform-cpt.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.extract_sentiment.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ""
  }
  depends_on = [aws_lambda_permission.allow_bucket]
}
