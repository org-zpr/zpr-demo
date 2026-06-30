#!/usr/bin/env bash
# Populate .env (gitignored) with the OCI IoT bridge credentials from Terraform.
# Run after `tofu apply` in ../../oci-iot. `docker compose` reads .env automatically.
set -euo pipefail
export PATH="$HOME/bin:$PATH"
TF_DIR="$(cd "$(dirname "$0")/../../oci-iot" && pwd)"
cd "$(dirname "$0")"

{
  echo "OCI_DEVICE_HOST=$(tofu -chdir="$TF_DIR" output -raw iot_device_host)"
  echo "OCI_DEVICE_USERNAME=$(tofu -chdir="$TF_DIR" output -raw device_a_username)"
  echo "OCI_DEVICE_PASSWORD=$(tofu -chdir="$TF_DIR" output -raw device_a_password)"
} > .env
chmod 600 .env
echo "Wrote $(pwd)/.env (gitignored, 0600)."
