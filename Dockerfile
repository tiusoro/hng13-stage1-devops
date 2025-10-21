# Use Ubuntu as the base image
FROM ubuntu:22.04

# Update package list and install Nginx
RUN apt-get update -y && \
    apt-get install -y nginx && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy the index.html file into the default Nginx web directory
# Assume index.html is in the same directory as this Dockerfile during build
COPY index.html /var/www/html/index.html

# Expose port 80 for HTTP traffic
EXPOSE 80

# Start Nginx in the foreground (non-daemon mode) when the container runs
CMD ["nginx", "-g", "daemon off;"]

