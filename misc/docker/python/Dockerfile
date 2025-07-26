FROM python:3.12-alpine

# Tạo một non-root user và group
# Nên chọn một UID/GID không phải 0 (root) và không quá thấp (thường 1000 trở lên)
ARG UID=1000
ARG GID=1000
RUN addgroup -g ${GID} appgroup && adduser -S -u ${UID} -G appgroup appuser

WORKDIR /app

# Đảm bảo thư mục làm việc thuộc sở hữu của user mới
RUN chown -R appuser:appgroup /app

USER appuser

CMD ["python", "-m", "metan.cli.main", "worker", "start"]