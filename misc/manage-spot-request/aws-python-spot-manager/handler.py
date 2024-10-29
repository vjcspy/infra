import os
import boto3
import logging

# Thiết lập logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ec2_client = boto3.client('ec2')

    spot_fleet_request_id = os.getenv('SPOT_FLEET_REQUEST_ID')
    new_target_capacity = int(os.getenv('NEW_TARGET_CAPACITY'))

    try:
        # Lấy thông tin hiện tại của Spot Fleet Request
        describe_response = ec2_client.describe_spot_fleet_requests(
            SpotFleetRequestIds=[spot_fleet_request_id]
        )

        if not describe_response['SpotFleetRequestConfigs']:
            logger.error(f"Spot Fleet Request ID {spot_fleet_request_id} không tồn tại.")
            return {
                'statusCode': 404,
                'body': f"Spot Fleet Request ID {spot_fleet_request_id} không tồn tại."
            }

        current_target_capacity = describe_response['SpotFleetRequestConfigs'][0]['SpotFleetRequestConfig']['TargetCapacity']
        logger.info(f"Current Target Capacity: {current_target_capacity}")
        logger.info(f"New Target Capacity: {new_target_capacity}")

        # So sánh và chỉ thay đổi nếu cần thiết
        if current_target_capacity != new_target_capacity:
            logger.info("Đang thay đổi target capacity...")
            modify_response = ec2_client.modify_spot_fleet_request(
                SpotFleetRequestId=spot_fleet_request_id,
                TargetCapacity=new_target_capacity
            )
            logger.info(f"Response từ modify_spot_fleet_request: {modify_response}")

            return {
                'statusCode': 200,
                'body': f'Successfully modified target capacity từ {current_target_capacity} thành {new_target_capacity}.'
            }
        else:
            logger.info("Target capacity hiện tại đã khớp với giá trị mới. Không cần thay đổi.")
            return {
                'statusCode': 200,
                'body': f'Target capacity hiện tại đã là {current_target_capacity}. Không thay đổi.'
            }

    except Exception as e:
        # Log lỗi nếu có
        logger.error(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': f'Error: {str(e)}'
        }
