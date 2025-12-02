FROM node:14 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install
COPY . .
RUN GENERATE_SOURCEMAP=false npm run build

FROM bitnami/nginx:latest
COPY --from=build /app/build /app
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]