FROM ubuntu:24.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    openssh-client \
    iproute2 \
    ca-certificates \
    libpcap-dev


# Set default workdir
WORKDIR /app


# valkey
ARG VALKEY_VERSION=7.2.11
RUN wget -O "valkey-${VALKEY_VERSION}.tar.gz" "https://github.com/valkey-io/valkey/archive/refs/tags/${VALKEY_VERSION}.tar.gz" \
&& tar xf "valkey-${VALKEY_VERSION}.tar.gz" \
&& cd "valkey-${VALKEY_VERSION}" \
&& make && make install \
&& cd /app \ 
&& rm -rf "valkey-${VALKEY_VERSION}" && rm "valkey-${VALKEY_VERSION}.tar.gz"



# These copy into {WORKDIR}/{dname}
# Note that docker does not like relative source paths here.
COPY src/build/bin bin
COPY release/db db

