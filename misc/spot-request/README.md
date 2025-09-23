```shell
aws ec2 request-spot-fleet \
    --spot-fleet-request-config file://spot_fleet_request.json \
    --region ap-southeast-1 \
    --profile ggg
```