FROM ubuntu:24.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
		openssh-client \
    iproute2 \
    ca-certificates
# Set default workdir
WORKDIR /app

# These copy into {WORKDIR}/{dname}
COPY bin bin
COPY db db
COPY certs certs

