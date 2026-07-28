#!/usr/bin/env bash
# Run vs-admin (locally) against zpr-core's visa service admin API, over an SSH tunnel.
# The admin API listens on [fd5a:5052::1]:8182 (a ZPR address on tun8), only reachable
# on zpr-core itself — so we SSH-forward a local port to it. Because the forwarded
# connection originates ON zpr-core, it counts as "same host" and needs no extra ZPR
# policy.
#
# Usage:  ./vs-admin.sh <vs-admin args...>
#   e.g.  ./vs-admin.sh actors
#         ./vs-admin.sh policies --curr
#         ./vs-admin.sh stats
#
# Prereqs: a key exists in the vs keys file and its full string is in ./.vs-admin.key
# (created via vsapikey on zpr-core). Override paths with env vars if needed.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/sources.env" ] && . "$HERE/sources.env"
source "$HERE/lib.sh"

# A plain laptop debug build, NOT an OL9 build: vs-admin runs locally over the SSH
# tunnel and never ships to an instance. The CA lives in this repo, so derive it.
VSADMIN="${VSADMIN:-${ZPR_VS_SRC:-}/target/debug/vs-admin}"
VS_CA="${VS_CA:-$HERE/../setup/authority/auth-ca.crt}"
KEYFILE_DEFAULT="$HERE/.vs-admin.key"
KEYFILE="${VS_KEYFILE:-$KEYFILE_DEFAULT}"
LPORT="${VS_LPORT:-8182}"

[ -x "$VSADMIN" ] || { echo "vs-admin not found/executable: $VSADMIN (build it: cd \$ZPR_VS_SRC && cargo build -p vs-admin)" >&2; exit 1; }
[ -f "$VS_CA" ] || { echo "CA cert not found: $VS_CA" >&2; exit 1; }

# Keep the auto-managed key in sync with the running core. cloud-init regenerates the
# key on every fresh instance (into $ZPR_DIR/vs/admin-api.key), so a cached local copy
# goes stale after a destroy/reapply and yields 401s. Always re-fetch the default key
# file; if the operator points VS_KEYFILE at their own key, use it untouched.
if [ "$KEYFILE" = "$KEYFILE_DEFAULT" ]; then
  ssh_core "sudo cat $ZPR_DIR/vs/admin-api.key" > "$KEYFILE" 2>/dev/null || true
  chmod 600 "$KEYFILE" 2>/dev/null || true
fi
[ -s "$KEYFILE" ] || { echo "no admin key available ($KEYFILE); fetch from zpr-core failed — was cloud-init keygen run?" >&2; exit 1; }

CTL="/tmp/vs-admin-tunnel.$$"
ssh "${SSH_OPTS[@]}" -M -S "$CTL" -f -N \
  -L "127.0.0.1:$LPORT:[fd5a:5052::1]:8182" "opc@$ZPR_CORE_IP"
trap 'ssh -S "$CTL" -O exit "opc@$ZPR_CORE_IP" 2>/dev/null' EXIT

"$VSADMIN" --svc-url "https://127.0.0.1:$LPORT" --ca-cert "$VS_CA" --api-key-file "$KEYFILE" "$@"
