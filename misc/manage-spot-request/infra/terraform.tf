terraform {
  backend "s3" {
    bucket         = "iz-terraform-state-bucket"  # Tên của S3 bucket
    key            = "aws-spot-manager/dev-container/terraform.tfstate"  # Đường dẫn đến file state trong bucket
    region         = "ap-southeast-1"  # Region của S3 bucket
    encrypt        = true
    # dynamodb_table = "my-lock-table"  # Tên DynamoDB Table (nếu sử dụng)
  }
}
