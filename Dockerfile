# Stage 1: Build React
FROM node:18 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install --legacy-peer-deps
COPY . .
RUN GENERATE_SOURCEMAP=false npm run build

# Stage 2: Serve with Alpine Nginx
FROM nginx:alpine

# 1. Security Patch (Keep Trivy happy)
RUN apk update && apk upgrade libpng

# 2. Copy Build Artifacts
COPY --from=build /app/build /usr/share/nginx/html

# 3. CRITICAL FIX: Change Nginx Listen Port from 80 to 8080
# This matches your Terraform Target Group settings.
RUN sed -i 's/listen  80;/listen 8080;/' /etc/nginx/conf.d/default.conf
# 4. Expose the new port
EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]