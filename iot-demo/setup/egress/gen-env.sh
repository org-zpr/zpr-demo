#!/usr/bin/env bash
# Populate .env (gitignored) with the OCI IoT bridge credentials from Terraform.
# Run after `tofu apply` in ../../oci-iot. `docker compose` reads .env automatically.
set -euo pipefail
export PATH="$HOME/bin:$PATH"
TF_DIR="$(cd "$(dirname "$0")/../../oci-iot" && pwd)"
cd "$(dirname "$0")"

# Assign first: inside echo "...$(tofu ...)", a failing tofu is masked by echo's
# exit 0 and set -e never fires. As an assignment, the substitution's failure is
# the assignment's exit status, so set -e aborts on a bad `tofu output`.
OCI_DEVICE_HOST="$(tofu -chdir="$TF_DIR" output -raw iot_device_host)"
OCI_DEVICE_USERNAME="$(tofu -chdir="$TF_DIR" output -raw device_a_username)"
OCI_DEVICE_PASSWORD="$(tofu -chdir="$TF_DIR" output -raw device_a_password)"

# Guard against empty-but-successful values before writing credentials.
for v in OCI_DEVICE_HOST OCI_DEVICE_USERNAME OCI_DEVICE_PASSWORD; do
  [ -n "${!v}" ] || { echo "ERROR: $v is empty — is the OCI stack applied?" >&2; exit 1; }
done

{
  printf 'OCI_DEVICE_HOST=%s\n' "$OCI_DEVICE_HOST"
  printf 'OCI_DEVICE_USERNAME=%s\n' "$OCI_DEVICE_USERNAME"
  printf 'OCI_DEVICE_PASSWORD=%s\n' "$OCI_DEVICE_PASSWORD"
} > .env
chmod 600 .env
echo "Wrote $(pwd)/.env (gitignored, 0600)."
