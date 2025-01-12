FROM alpine:3.19

# Tạo thư mục app
WORKDIR /app

# Copy binary file vào image
COPY dvt-splunk_licsrv.1.0.linux.amd64 .

# Phân quyền execute cho binary
RUN chmod +x /app/dvt-splunk_licsrv.1.0.linux.amd64

# Expose port 3001
EXPOSE 3001

# Chạy license server
CMD ["/app/dvt-splunk_licsrv.1.0.linux.amd64", "-port", "3001"]