## Usage
> Giả sử bạn đã clone/pull code về, thì các bước:

1. Init (khởi tạo lại provider và backend S3):

```terraform init```


2. Xem thay đổi (rất quan trọng trước khi apply):

```terraform plan```


Command này sẽ so sánh state trong S3 với code mới, rồi show cho bạn biết sẽ tạo/sửa/xoá resource nào.

3. Apply thay đổi:

```terraform apply```