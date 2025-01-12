# Sử dụng Ubuntu 22.04 làm base image
FROM ubuntu:24.04

# Thêm labels
LABEL org.opencontainers.image.ref.name=ubuntu
LABEL org.opencontainers.image.version=24.04

# Thiết lập thư mục làm việc
WORKDIR /app

# Sao chép file start.sh và thiết lập quyền
COPY ./start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Set shell mặc định
SHELL ["/bin/bash", "-c"]

# Thiết lập command khi container khởi động
CMD ["/app/start.sh"]