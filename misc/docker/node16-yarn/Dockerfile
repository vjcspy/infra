# Sử dụng Node.js phiên bản 20 Alpine
FROM node:16-alpine

# Cài đặt Yarn
#RUN npm install -g yarn@latest

# Kiểm tra phiên bản Yarn
RUN yarn --version

# Tạo nhóm và người dùng non-root với UID và GID cố định
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nodejsuser

# Thiết lập thư mục làm việc và gán quyền sở hữu
WORKDIR /app
RUN chown nodejsuser:nodejs /app

# Chuyển sang người dùng non-root
USER nodejsuser

# Expose cổng ứng dụng
EXPOSE 3000

# Lệnh mặc định
CMD ["yarn", "-v"]
