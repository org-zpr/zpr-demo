#!/usr/bin/env bash
# Build ph/vs for Oracle Linux 9 (glibc 2.34) inside an OL9 container.
#
# Why: binaries built on the dev laptop link against a newer glibc (2.38/2.39)
# and will NOT run on OL9 ("GLIBC_2.38 not found"). Building in an oraclelinux:9
# container links against glibc 2.34, matching the OCI compute instances.
# musl static builds were ruled out — ph/vs pull in openssl-sys + aws-lc-sys
# (cmake-built C crypto), which fight musl.
#
# Output goes to a SEPARATE target dir (zpr/oci-build/release/) so it doesn't
# clobber the laptop's own target/release/ builds. The oci-compute Terraform's
# ph_binary_path / vs_binary_path point here.
#
# Requires Docker (via sudo on this host). Run from anywhere.
set -euo pipefail

ZPR_ROOT="${ZPR_ROOT:-/home/othomas/zpr}"

sudo docker run --rm -v "$ZPR_ROOT:/src" -w /src -e CARGO_TARGET_DIR=/src/oci-build oraclelinux:9 bash -c '
  set -e
  # oracle-epel-release-el9 defines the EPEL repo (disabled); capnproto lives there.
  # libpcap-devel lives in CodeReady Builder (also disabled). Enable both to install.
  dnf install -y oracle-epel-release-el9
  dnf install -y --enablerepo=ol9_developer_EPEL,ol9_codeready_builder \
    gcc gcc-c++ cmake perl openssl-devel pkgconf-pkg-config capnproto libpcap-devel
  curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  . "$HOME/.cargo/env"
  cargo build --release --manifest-path core/Cargo.toml
  cargo build --release --manifest-path visaservice/Cargo.toml
  # container runs as root; hand the output back to the owner of the mounted tree
  chown -R $(stat -c %u:%g /src) /src/oci-build
'

echo
echo "Built:"
ls -la "$ZPR_ROOT/oci-build/release/ph" "$ZPR_ROOT/oci-build/release/vs"
echo "Verify glibc requirement is <= 2.34:"
objdump -T "$ZPR_ROOT/oci-build/release/ph" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1
