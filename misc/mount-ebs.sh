#!/bin/bash
set -e  # Dừng script nếu có lỗi xảy ra

# Cấu hình AWS Credentials - Thay đổi giá trị cho phù hợp
export AWS_ACCESS_KEY_ID="xxx"
export AWS_SECRET_ACCESS_KEY="xxx"
export AWS_DEFAULT_REGION="ap-southeast-1"  # Đặt region mặc định nếu cần

# Update system
yum update -y

# Install AWS CLI nếu chưa có sẵn
if ! command -v aws &> /dev/null; then
    yum install -y aws-cli
fi

# Lấy Instance ID của instance hiện tại
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
echo "Instance ID: $INSTANCE_ID"

# Kiểm tra trạng thái của volume và instance đang gắn
VOLUME_ID="vol-03bb59d3251b98526"
REGION="ap-southeast-1"

# Lấy thông tin đính kèm của volume
echo "Getting current volume status"
attached_instance_id=$(aws ec2 describe-volumes --volume-ids $VOLUME_ID --region $REGION --query "Volumes[0].Attachments[0].InstanceId" --output text)
volume_status=$(aws ec2 describe-volumes --volume-ids $VOLUME_ID --region $REGION --query "Volumes[0].State" --output text)
echo "attached_instance_id: $attached_instance_id"
echo "volume_status: $volume_status"

need_to_attach=true
# Nếu volume đã được gắn vào đúng instance hiện tại, không làm gì
if [ "$volume_status" == "in-use" ] && [ "$attached_instance_id" == "$INSTANCE_ID" ]; then
    echo "Volume $VOLUME_ID đã được gắn vào instance hiện tại ($INSTANCE_ID). Không cần thực hiện thêm thao tác attach volume."
    need_to_attach=false
# Nếu volume đã được gắn vào một instance khác
elif [ "$volume_status" == "in-use" ] && [ "$attached_instance_id" != "None" ] && [ "$attached_instance_id" != "$INSTANCE_ID" ]; then
    echo "Volume $VOLUME_ID hiện đang được gắn vào instance khác ($attached_instance_id). Đang tháo..."
    aws ec2 detach-volume --volume-id "$VOLUME_ID" --region "$REGION" || { echo "Failed to detach volume. Exiting."; exit 1; }

    # Chờ để volume chuyển sang trạng thái 'available'
    echo "Đợi volume trở về trạng thái 'available'..."
    while true; do
        volume_status=$(aws.ec2.describe-volumes --volume-ids $VOLUME_ID --region $REGION --query "Volumes[0].State" --output text)
        if [ "$volume_status" == "available" ]; then
            break
        fi
        sleep 5
    done
    echo "Volume đã được tháo thành công."
fi

if [ "$need_to_attach" = true ]; then
    # Attach the existing EBS volume to this instance
    echo "Đang gắn volume $VOLUME_ID vào instance $INSTANCE_ID..."
    aws ec2 attach-volume --volume-id "$VOLUME_ID" --instance-id "$INSTANCE_ID" --device /dev/sdb --region "$REGION" || { echo "Failed to attach volume. Exiting."; exit 1; }

    # Chờ để volume được gắn hoàn tất
    echo "Đợi volume được gắn..."
    while [ "$(aws ec2 describe-volumes --volume-ids $VOLUME_ID --region $REGION --query "Volumes[0].Attachments[0].State" --output text)" != "attached" ]; do
        sleep 5
    done
    echo "Volume đã được gắn thành công."
fi

# Tạo thư mục mount nếu chưa tồn tại
MOUNT_POINT="/mnt/existing_ebs_volume"
if [ ! -d "$MOUNT_POINT" ]; then
    mkdir -p $MOUNT_POINT
fi

# Mount volume (giả định định dạng là ext4, điều chỉnh nếu cần)
echo "Đang mount volume..."
mount /dev/sdb "$MOUNT_POINT" || { echo "Failed to mount volume. Exiting."; exit 1; }

# Thêm vào /etc/fstab để mount tự động khi khởi động lại
#if ! grep -qs '/mnt/existing_ebs_volume' /etc/fstab; then
#    echo '/dev/sdb /mnt/existing_ebs_volume ext4 defaults,nofail 0 2' >> /etc/fstab
#    echo "Đã thêm vào /etc/fstab để mount tự động."
#fi

echo "Script hoàn tất."
