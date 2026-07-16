#!/usr/bin/env bash
# Deploy + run ZPR on the OCI hosts (PLAN.md §3 + §4). Implements
# tf-configure-run-zpr.md. Run after `tofu apply`, from anywhere:
#   ./deploy-zpr.sh
# Re-runnable: scp overwrites, ph is pkill'd before restart, addresses come
# straight from `tofu output`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # oci-compute/ = tofu root
MULTI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$MULTI_DIR/bin"
CONF_DIR="$MULTI_DIR/zpr-conf/confs"
INC_DIR="$MULTI_DIR/zpr-conf"        # include/… paths in configs are relative to here

KEY="${SSH_KEY:-$HOME/.ssh/zpr-demo}"
SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

tf()   { tofu -chdir="$SCRIPT_DIR" "$@"; }
ssh_h(){ ssh "${SSH_OPTS[@]}" "ubuntu@$1" "${@:2}"; }

# --- Step 0: addresses from tofu ---
NODE_PRIV=$(tf output -json private_ips | jq -r .node)
NODE_PUB=$(tf output -json public_ips   | jq -r .node)
WEB_PUB=$(tf output -json public_ips     | jq -r .webserver)
echo "node priv=$NODE_PRIV pub=$NODE_PUB ; webserver pub=$WEB_PUB"

# tun9 sanity — assume zpr-tun.service is green, fail loud if not.
check_tun9() {  # $1=pubip $2=label
  ssh_h "$1" "ip addr show tun9 >/dev/null 2>&1" \
    || { echo "ERROR: tun9 not up on $2 ($1) — check zpr-tun.service" >&2; exit 1; }
  echo "[$2] tun9 up"
}

# --- Step 1: render *.toml.template -> scratch/*.toml, fail on leftover sentinel ---
render() {  # $1=template basename; echoes path to rendered file
  local out="$SCRATCH/${1%.template}"
  sed "s/@@NODE0_ADDR@@/${NODE_PRIV}/" "$CONF_DIR/$1" > "$out"
  if grep -n '@@[A-Z0-9_]*@@' "$out"; then
    echo "ERROR: unresolved template token(s) above in ${1%.template}" >&2
    exit 1
  fi
  echo "$out"
}

# --- Step 2: ph + one conf + only its referenced include files, + runtime dir ---
deploy_host() {  # $1=pubip $2=conf-path $3=label
  local ip="$1" conf="$2" label="$3"
  local -a inc
  mapfile -t inc < <(grep -oE 'include/[^"]+' "$conf" | sort -u)   # source of truth
  echo "[$label] deploying $(basename "$conf") + ${#inc[@]} include file(s)"
  ssh_h "$ip" "mkdir -p zpr/include"
  # ph is ~200 MB — skip the upload if the host already has the same-size binary.
  local sz; sz=$(stat -c%s "$BIN_DIR/ph")
  if ssh_h "$ip" "[ -x zpr/ph ] && [ \$(stat -c%s zpr/ph 2>/dev/null) = $sz ]"; then
    echo "[$label] ph already up-to-date, skipping binary upload"
  else
    scp "${SSH_OPTS[@]}" "$BIN_DIR/ph" "ubuntu@$ip:zpr/"
  fi
  scp "${SSH_OPTS[@]}" "$conf" "ubuntu@$ip:zpr/"
  scp "${SSH_OPTS[@]}" "${inc[@]/#/$INC_DIR/}" "ubuntu@$ip:zpr/include/"
  ssh_h "$ip" "sudo install -d -o ubuntu -g ubuntu /var/run/zpr"   # one sudo step
}

# --- Step 3: start ph inside a detached tmux session so it can be attached to ---
# Session name = mode (one ph per host). Re-run kills the old session first.
# Attach to watch output: ssh -t ubuntu@<host> tmux attach -t <mode>
start_ph() {  # $1=pubip $2=mode(node|adapter) $3=conf-basename $4=label
  ssh_h "$1" "tmux kill-session -t $2 2>/dev/null || true; \
    tmux new-session -d -s $2 -c ~/zpr './ph $2 -c ~/zpr/$3'; \
    sleep 1; tmux has-session -t $2 2>/dev/null \
      && echo '[$4] ph $2 running in tmux session \"$2\"' \
      || { echo 'ERROR: ph $2 exited immediately on $4' >&2; exit 1; }"
}

# =============================== run ===============================
check_tun9 "$NODE_PUB" node
check_tun9 "$WEB_PUB"  webserver

WEB_CONF=$(render adapter-web0-conf.toml.template)

# §4 step 2: node first.
deploy_host "$NODE_PUB" "$CONF_DIR/node0-conf.toml" node
start_ph    "$NODE_PUB" node node0-conf.toml node

# §4 step 4: web service already up from cloud-init — just verify.
ssh_h "$WEB_PUB" "curl -fsS http://localhost:80 >/dev/null" \
  && echo "[webserver] nginx serving :80" \
  || { echo "ERROR: nginx not serving on webserver" >&2; exit 1; }

# §4 step 5: web adapter, pointed at the now-up node.
deploy_host "$WEB_PUB" "$WEB_CONF" webserver
start_ph    "$WEB_PUB" adapter adapter-web0-conf.toml webserver

echo
echo "Done. Attach to a ph session to watch its output (Ctrl-b d to detach):"
echo "  ssh -i $KEY -t ubuntu@$NODE_PUB tmux attach -t node"
echo "  ssh -i $KEY -t ubuntu@$WEB_PUB  tmux attach -t adapter"
