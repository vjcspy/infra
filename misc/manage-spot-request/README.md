# Auto Schedule AWS Spot request

## Infra

Sử dụng Terraform để tạo IAM Role cho lambda sử dụng (Lambda function sẽ cần 1 số permission để modify spot request)
Output: `lambda-ec2-spot-scheduler-role`

## AWS Python serverless

Sửa `serverless.yaml` để config cho đúng:
- SPOT_FLEET_REQUEST_ID
- NEW_TARGET_CAPACITY

### Deploy
```shell
serverless deploy
```
