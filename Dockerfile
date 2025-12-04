# Stage 1: Build React
FROM node:18 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install --legacy-peer-deps
COPY . .
RUN GENERATE_SOURCEMAP=false npm run build

# Stage 2: Serve with Alpine Nginx
FROM nginx:alpine

# --- SECURITY PATCH START ---
# Trivy found CVE-2025-64720 in libpng. We force an upgrade here.
RUN apk update && apk upgrade libpng
# --- SECURITY PATCH END ---

# Copy the build output
COPY --from=build /app/build /usr/share/nginx/html

# Configure Nginx to listen on 8080 (For Non-Root security)
RUN sed -i 's/listen  80;/listen 8080;/' /etc/nginx/conf.d/default.conf

# Expose 8080
EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]