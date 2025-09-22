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
# Note that docker does not like relative source paths here.
COPY src/build/bin bin
COPY release/db db

