import boto3
import os

ec2 = boto3.client('ec2')


def check_spot_instance(event, context):
    spot_fleet_request_id = os.environ['SPOT_FLEET_REQUEST_ID']
    allocation_id = os.environ.get('ALLOCATION_ID', None)

    try:
        # Kiểm tra Spot Fleet Request
        spot_fleet_requests = ec2.describe_spot_fleet_requests(SpotFleetRequestIds=[spot_fleet_request_id])

        # Lấy thông tin các Spot Instances liên kết với Spot Fleet Request
        spot_fleet_instances = ec2.describe_spot_fleet_instances(SpotFleetRequestId=spot_fleet_request_id)
        spot_instance_ids = [instance['InstanceId'] for instance in spot_fleet_instances['ActiveInstances']]
        print(f"Number of spot instance {len(spot_instance_ids)}")


        if spot_instance_ids and len(spot_instance_ids) == 1:
            for spot_instance_id in spot_instance_ids:
                # Kiểm tra xem Instance đã có Elastic IP chưa
                instance = ec2.describe_instances(InstanceIds=[spot_instance_id])
                network_interfaces = instance['Reservations'][0]['Instances'][0]['NetworkInterfaces']

                for ni in network_interfaces:
                    current_allocation_id = ni.get('Association', {}).get('AllocationId', None)

                    # Kiểm tra nếu instance đã có Elastic IP và khác với allocation_id
                    if current_allocation_id:
                        if current_allocation_id == allocation_id:
                            print(f"Instance {spot_instance_id} đã có đúng Elastic IP.")
                            return
                        else:
                            print(f"Instance {spot_instance_id} có Elastic IP khác (Allocation ID hiện tại: {current_allocation_id}). Gán lại.")
                            ec2.disassociate_address(AssociationId=ni['Association']['AssociationId'])

                # Gán Elastic IP nếu chưa có hoặc khác
                if allocation_id:
                    ec2.associate_address(InstanceId=spot_instance_id, AllocationId=allocation_id)
                    print(f"Elastic IP {allocation_id} đã được gán cho instance {spot_instance_id}.")
        else:
            print(f"Spot Fleet Request {spot_fleet_request_id} chưa có instance nào.")

    except Exception as e:
        print(f"Lỗi: {str(e)}")
        # raise e
