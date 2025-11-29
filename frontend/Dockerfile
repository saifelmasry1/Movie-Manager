# Build stage
FROM node:18-alpine as build

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .
ARG VITE_API_BASE_URL
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
RUN npm run build

# Production stage
FROM node:18-alpine

WORKDIR /app

# Install serve to run the static files
RUN npm install -g serve

# Copy built assets from build stage
COPY --from=build /app/dist ./dist

# Expose port 3000
EXPOSE 3000

# Start the application
CMD ["serve", "-s", "dist", "-l", "3000"]
