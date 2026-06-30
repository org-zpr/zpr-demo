# oci-iot — OCI IoT Platform resources for the ZPR demo

Completes the `mosquitto → digital twin adapter → OCI IoT Platform` chain. IT pre-built
the IoT **domain** (`ZPR-Demo-Domain`); this root builds everything on top of it so
device_a's telemetry can reach the platform.

Uses **basic (vault-secret) auth** — Oracle's recommended path for testing — so there
is **no CA, no client certs, and no tenancy-level IAM**. Everything is created inside
the `ZPR-IoT-Demo` compartment.

## What this creates

Auth: **Vault → AES key → secret** (the device password).

Data path: **digital twin model → adapter → secret-auth instance** on the existing domain.

The existing domain + domain group are *referenced by OCID*, never managed here.
State is local (`terraform.tfstate`, gitignored).

## Prerequisites

- OpenTofu / Terraform ≥ 1.6
- `~/.oci/config` profile `DEFAULT`
- Rights to create Vault/KMS, Vault secrets, and IoT resources in `ZPR-IoT-Demo`
  (no tenancy-root rights needed).

## Apply

```bash
tofu init
tofu plan
tofu apply
```

Vaults take ~60s to create.

## After apply — wire up mosquitto

Basic auth = MQTT username/password over TLS (no client cert):

```bash
tofu output -raw device_a_password    # the MQTT password
tofu output device_a_username          # "device-a"
tofu output iot_device_host            # broker host
```

Add a bridge `connection` to the egress mosquitto:

```conf
connection oci_iot_device_a
address <iot_device_host>:8883
bridge_capath /etc/ssl/certs            # validate OCI's server cert (public CA)
bridge_protocol_version mqttv311
remote_username device-a
remote_password <device_a_password>
topic "" out 1 devices/device-a/telemetry iot/v1/telemetry
```

## device_a timestamp

device_a.py emits `YYYY-MM-DDTHH:MM:SS.ffffffZ` (microseconds + Z), which the OCI
adapter requires. (Fixed; previously was seconds-only.)

## Upgrading to mTLS later

For a production-grade demo, swap the secret for an mTLS client certificate. That
reintroduces a Root CA, which needs a tenancy-level dynamic group + policy (the CA
acts as a resource principal) — typically created once by IT.
