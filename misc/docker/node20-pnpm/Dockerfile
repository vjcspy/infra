# Dockerfile
FROM node:20-alpine

# Cài đặt pnpm thông qua corepack (built-in với Node.js)
RUN npm install -g pnpm@latest
# Kiểm tra phiên bản pnpm để xác nhận
RUN pnpm --version

# Tạo non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nodejsuser

# Set working directory và permissions
WORKDIR /app
RUN chown nodejsuser:nodejs /app

# Chuyển sang non-root user
USER nodejsuser

# Set production environment
ENV NODE_ENV=production

# Expose port mặc định
EXPOSE 3000

# Command mặc định
CMD ["pnpm", "-v"]