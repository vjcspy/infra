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
          "ec2:DescribeSpotFleetInstances"      # Thêm quyền describe spot fleet requests
        ],
        Effect   = "Allow",
        Resource = "*"
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
