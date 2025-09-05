resource "aws_iam_role" "lambda_ec2_role" {
  name = "lambda-ec2-spot-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_iam_policy" "lambda_ec2_policy" {
  name = "lambda-ec2-spot-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ec2:DescribeSpotInstanceRequests",
          "ec2:ModifySpotFleetRequest",
          "ec2:AllocateAddress",       # Thêm quyền allocate Elastic IP
          "ec2:AssociateAddress",      # Thêm quyền associate Elastic IP
          "ec2:DescribeInstances",      # Thêm quyền describe instances
          "ec2:DescribeSpotFleetRequests",      # Thêm quyền describe spot fleet requests
          "ec2:DescribeSpotFleetInstances",      # Thêm quyền describe spot fleet requests
          "ec2:RebootInstances",
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        Effect = "Allow",
        Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/common"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.lambda_ec2_role.name
  policy_arn = aws_iam_policy.lambda_ec2_policy.arn
}
