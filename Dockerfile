#Base image
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    iproute2 iputils-ping net-tools sudo \
    libssl-dev openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create app working directory
WORKDIR /app

# Copy precompiled ZPR binaries and make them executable
COPY ./bin /bin
RUN chmod +x /bin/*

# Copy configuration files (can be overridden by volumes in docker-compose)
COPY ./config /config

# Default command (overridden by docker-compose)
CMD ["bash"]

