# Sử dụng Node.js phiên bản 20 Alpine
FROM node:16-alpine

# Kiểm tra phiên bản Yarn
RUN yarn --version

# Tạo nhóm và người dùng non-root với UID và GID cố định
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nodejsuser

# Thiết lập thư mục làm việc và gán quyền sở hữu
WORKDIR /app
RUN chown 1001:1001 /app

# Permission for build
RUN mkdir -p /home/nodejsuser/.npm && \
    mkdir -p /home/nodejsuser/.cache/yarn && \
    chown -R 1001:1001 /home/nodejsuser/.npm && \
    chown -R 1001:1001 /home/nodejsuser/.cache

# Nếu cần thiết, có thể thêm quyền ghi cho /tmp
RUN chmod 777 /tmp

# Chuyển sang người dùng non-root
USER 1001

# Expose cổng ứng dụng
EXPOSE 3000

# Lệnh mặc định
CMD ["yarn", "-v"]