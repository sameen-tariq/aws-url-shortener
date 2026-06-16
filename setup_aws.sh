#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# setup_aws.sh — One-time AWS infrastructure provisioning script
# Run ONCE before the CI/CD pipeline to create the required resources
# Usage: bash setup_aws.sh
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Configuration — edit these before running ────────────────────
AWS_REGION="ap-southeast-1"        # Change to your preferred region
S3_BUCKET="url-shortener-1781598110"
LAMBDA_ROLE_NAME="url-shortener-lambda-role"
ECR_REPO_NAME="url-shortener-admin"
ECS_CLUSTER_NAME="url-shortener-cluster"
ECS_SERVICE_NAME="url-shortener-admin-svc"
EC2_KEY_NAME="url-shortener-key"   # Your existing EC2 key pair name
# ─────────────────────────────────────────────────────────────────

echo "==> [1/8] Using existing S3 bucket: $S3_BUCKET"
aws s3api create-bucket --bucket "$S3_BUCKET" --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" 2>/dev/null || true
aws s3api put-bucket-versioning --bucket "$S3_BUCKET" \
  --versioning-configuration Status=Enabled
aws s3 website "s3://$S3_BUCKET" --index-document index.html --error-document error.html
echo "    Bucket created: $S3_BUCKET"

echo ""
echo "==> [2/8] Creating IAM role for Lambda"
TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}'
ROLE_ARN=$(aws iam create-role \
  --role-name "$LAMBDA_ROLE_NAME" \
  --assume-role-policy-document "$TRUST_POLICY" \
  --query 'Role.Arn' --output text)
aws iam attach-role-policy --role-name "$LAMBDA_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam put-role-policy --role-name "$LAMBDA_ROLE_NAME" \
  --policy-name S3Access \
  --policy-document "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[{
      \"Effect\":\"Allow\",
      \"Action\":[\"s3:GetObject\",\"s3:PutObject\"],
      \"Resource\":\"arn:aws:s3:::$S3_BUCKET/urls/*\"
    }]
  }"
echo "    Role ARN: $ROLE_ARN"
echo "    Waiting 10s for IAM propagation..."
sleep 10

echo ""
echo "==> [3/8] Creating Lambda function: url-shortener-shorten"

(cd lambda/shorten && zip -r ../../shorten.zip .)

aws lambda create-function \
  --function-name url-shortener-shorten \
  --runtime python3.12 \
  --role "$ROLE_ARN" \
  --handler lambda_shorten.lambda_handler \
  --zip-file fileb://shorten.zip \
  --environment "Variables={S3_BUCKET=$S3_BUCKET,BASE_URL=https://your-api-id.execute-api.$AWS_REGION.amazonaws.com}" \
  --region "$AWS_REGION"

echo ""
echo "==> [4/8] Creating Lambda function: url-shortener-redirect"

(cd lambda/redirect && zip -r ../../redirect.zip .)

aws lambda create-function \
  --function-name url-shortener-redirect \
  --runtime python3.12 \
  --role "$ROLE_ARN" \
  --handler lambda_redirect.lambda_handler \
  --zip-file fileb://redirect.zip \
  --environment "Variables={S3_BUCKET=$S3_BUCKET}" \
  --region "$AWS_REGION"

echo ""
echo "==> [5/8] Creating API Gateway (HTTP API)"
API_ID=$(aws apigatewayv2 create-api \
  --name url-shortener-api \
  --protocol-type HTTP \
  --cors-configuration AllowOrigins='["*"]',AllowMethods='["GET","POST"]',AllowHeaders='["Content-Type"]' \
  --query 'ApiId' --output text --region "$AWS_REGION")
echo "    API ID: $API_ID"

echo ""
echo "==> [6/8] Creating ECR repository for admin dashboard"
aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$AWS_REGION" || true
ECR_URI=$(aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" \
  --query 'repositories[0].repositoryUri' --output text --region "$AWS_REGION")
echo "    ECR URI: $ECR_URI"

echo ""
echo "==> [7/8] Creating ECS cluster"
aws ecs create-cluster --cluster-name "$ECS_CLUSTER_NAME" --region "$AWS_REGION"
echo "    Cluster created: $ECS_CLUSTER_NAME"

echo ""
echo "==> [8/8] Launching EC2 bastion instance (t3.micro)"
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --key-name "$EC2_KEY_NAME" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=url-shortener-bastion}]" \
  --query 'Instances[0].InstanceId' --output text --region "$AWS_REGION")
echo "    EC2 Instance ID: $INSTANCE_ID"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  SETUP COMPLETE — add these to GitHub Secrets before pushing:"
echo "══════════════════════════════════════════════════════════════"
echo "  AWS_ACCESS_KEY_ID     = <your key>"
echo "  AWS_SECRET_ACCESS_KEY = <your secret>"
echo "  AWS_REGION            = $AWS_REGION"
echo "  S3_BUCKET             = $S3_BUCKET"
echo "  ECR_REPOSITORY        = $ECR_REPO_NAME"
echo "  ECS_CLUSTER           = $ECS_CLUSTER_NAME"
echo "  ECS_SERVICE           = $ECS_SERVICE_NAME"
echo "══════════════════════════════════════════════════════════════"
