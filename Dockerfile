FROM node:14 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install
COPY . .
RUN GENERATE_SOURCEMAP=false npm run build

FROM nginx:alpine
COPY --from=build /app/build /app
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]