#!/usr/bin/env bash
# Preflight dependency check — run BEFORE ./post-init.sh / ./start-device-*.sh.
# SSHes to all three instances and verifies every runtime dependency that cloud-init is
# supposed to have installed/downloaded: the ph/vs/vsapikey binaries (and that their
# shared libs — glibc, openssl/libssl, libpcap — all resolve), the EPEL packages
# (valkey, mosquitto), the TLS CA bundle, and every cert/key/policy/config file each
# role needs. Prints OK/MISSING per item; exits non-zero if anything is missing, so you
# never start the demo on a half-provisioned instance (the OCI network-at-boot flakiness
# can silently break a dnf/pip/curl step).
source "$(dirname "$0")/lib.sh"

RED=$'\e[31m'; GRN=$'\e[32m'; RST=$'\e[0m'
fail=0

# chk <ssh_fn> <label> <remote test command>
chk() {
  local fn="$1" label="$2" cmd="$3"
  if $fn "$cmd" >/dev/null 2>&1; then
    printf '  %sOK%s      %s\n' "$GRN" "$RST" "$label"
  else
    printf '  %sMISSING%s %s\n' "$RED" "$RST" "$label"
    fail=1
  fi
}

# a binary is "good" if it exists, is executable, and has no unresolved shared libs
# (this is the openssl/glibc/libpcap check).
runnable() { echo "test -x $1 && ! ldd $1 2>&1 | grep -q 'not found'"; }

echo "== zpr-core ($ZPR_CORE_IP) =="
chk ssh_core "binary ph      (+ shared libs resolve)"  "$(runnable /usr/local/bin/ph)"
chk ssh_core "binary vs      (+ shared libs resolve)"  "$(runnable /usr/local/bin/vs)"
chk ssh_core "binary vsapikey"                         "test -x /usr/local/bin/vsapikey"
chk ssh_core "pkg valkey (valkey-cli)"                 "command -v valkey-cli"
chk ssh_core "pkg mosquitto"                           "command -v mosquitto"
chk ssh_core "openssl CLI"                             "command -v openssl"
chk ssh_core "TLS CA bundle (bridge)"                  "test -s /etc/pki/tls/certs/ca-bundle.crt"
chk ssh_core "mosquitto loads conf.d"                  "grep -q '^include_dir /etc/mosquitto/conf.d' /etc/mosquitto/mosquitto.conf"
chk ssh_core "policy iot-demo.bin2"                    "test -s $ZPR_DIR/iot-demo.bin2"
chk ssh_core "CA cert"                                 "test -s $ZPR_DIR/authority/auth-ca.crt"
chk ssh_core "node key material"                       "test -s $ZPR_DIR/node/node-noise.crt && test -s $ZPR_DIR/node/node-noise.key && test -s $ZPR_DIR/node/node-private-key.pem && test -s $ZPR_DIR/node/node-noise-pub.pem"
chk ssh_core "vs key material"                         "test -s $ZPR_DIR/vs/vs-noise.crt && test -s $ZPR_DIR/vs/vs-noise.key && test -s $ZPR_DIR/vs/vs-private-key.pem && test -s $ZPR_DIR/vs/admin-tls-cert.pem && test -s $ZPR_DIR/vs/admin-tls-key.pem"
chk ssh_core "egress key material"                     "test -s $ZPR_DIR/egress/egress-noise.crt && test -s $ZPR_DIR/egress/egress-noise.key && test -s $ZPR_DIR/egress/egress-private-key.pem"
chk ssh_core "rendered configs"                        "test -s $ZPR_DIR/node/node-conf.toml && test -s $ZPR_DIR/vs/vs-conf.toml && test -s $ZPR_DIR/vs/adapter-vs-conf.toml && test -s $ZPR_DIR/egress/egress-adapter-conf.toml"

# check_device <ssh_fn> <name: device-a|device-b> <ip> <device script>
check_device() {
  local dfn="$1" name="$2" ip="$3" script="$4"
  echo "== $name ($ip) =="
  chk "$dfn" "binary ph      (+ shared libs resolve)" "$(runnable /usr/local/bin/ph)"
  chk "$dfn" "python3"                                "command -v python3"
  chk "$dfn" "python dep paho-mqtt"                   "python3 -c 'import paho.mqtt.client'"
  chk "$dfn" "CA cert"                                "test -s $ZPR_DIR/authority/auth-ca.crt"
  chk "$dfn" "node pubkey"                            "test -s $ZPR_DIR/node/node-noise-pub.pem"
  chk "$dfn" "adapter key material"                   "test -s $ZPR_DIR/$name/$name-noise.crt && test -s $ZPR_DIR/$name/$name-noise.key && test -s $ZPR_DIR/$name/$name-private-key.pem"
  chk "$dfn" "adapter config"                         "test -s $ZPR_DIR/$name/$name-adapter-conf.toml"
  chk "$dfn" "device script $script"                  "test -s $ZPR_DIR/devices/$script"
}

check_device ssh_devA device-a "$DEVICE_A_IP" device_a.py
check_device ssh_devB device-b "$DEVICE_B_IP" device_b.py

echo
if [ "$fail" -eq 0 ]; then
  echo "${GRN}PREFLIGHT PASSED${RST} — all dependencies present. Safe to run post-init / start-device."
else
  echo "${RED}PREFLIGHT FAILED${RST} — install the MISSING items before running the devices."
  echo "ssh -i ~/.ssh/zpr-demo opc@$(tofu output -raw device_a_public_ip) \ "
  echo "  (paho on a device:  sudo dnf install -y python3-pip && sudo pip3 install paho-mqtt)"
  echo "  (valkey/mosquitto on zpr-core:  sudo dnf install -y --enablerepo=ol9_developer_EPEL valkey mosquitto)"
fi
exit "$fail"
