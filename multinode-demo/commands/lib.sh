#!/usr/bin/env bash
# Shared helpers for the demo-* operator commands. SOURCED, not executed.
#
# One name table for the six ZPR `ph` processes across both environments, plus a
# single ssh-vs-docker dispatch point (`on` / `on_tty`). Everything else in
# commands/ is a thin wrapper over these.
#
# Names match the adapter CNs in the policy, so they read the same here and in
# the ph logs. See ../scripts-plan.md for the full table.
set -euo pipefail

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "lib.sh is a sourced library; run one of the demo-* commands" >&2
  exit 1
fi

MULTI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # multinode-demo/
LOGS_DIR="$MULTI_DIR/local-compute/logs"

KEY="${SSH_KEY:-$HOME/.ssh/zpr-demo}"
SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

# --- the name table ---------------------------------------------------------
# TARGET  : oci -> `tofu output` key; docker -> container name
# SESSION : tmux session holding that ph (also the oci log basename)
# LOG     : oci -> path on the host; docker -> path on THIS host (mounted volume)
# LAUNCH  : the command the deploy script used, replayed by demo-restart-ph
# WD      : cwd for the tmux session
# SUDO    : "sudo " prefix, or empty
NAMES=(node0 ociweb alice node1 vs premweb)

declare -A KIND=(
  [node0]=oci   [ociweb]=oci      [alice]=oci
  [node1]=docker [vs]=docker      [premweb]=docker
)
declare -A TARGET=(
  [node0]=node  [ociweb]=webserver [alice]=alice
  [node1]=node1 [vs]=vs            [premweb]=web1
)
declare -A SESSION=(
  [node0]=node  [ociweb]=adapter   [alice]=adapter
  [node1]=node1 [vs]=vs-adapter    [premweb]=web1-adapter
)
declare -A LOG=(
  [node0]='$HOME/zpr/node.log'
  [ociweb]='$HOME/zpr/adapter.log'
  [alice]='$HOME/zpr/adapter.log'
  [node1]="$LOGS_DIR/node1.log"
  [vs]="$LOGS_DIR/vs-adapter.log"
  [premweb]="$LOGS_DIR/web1-adapter.log"
)
declare -A LAUNCH=(
  [node0]='./ph node -c ~/zpr/node0-conf.toml'
  [ociweb]='./ph adapter -c ~/zpr/adapter-web0-conf.toml'
  [alice]='sudo ./ph adapter -c ~/zpr/adapter-alice-conf.toml'
  [node1]='/app/bin/ph node -c node1-conf.toml'
  [vs]='/app/bin/ph adapter -c adapter-vs-conf.toml'
  [premweb]='/app/bin/ph adapter -c adapter-web1-conf.toml'
)
declare -A WD=(
  [node0]='$HOME/zpr' [ociweb]='$HOME/zpr' [alice]='$HOME/zpr'
  [node1]=/conf       [vs]=/conf           [premweb]=/conf
)
# alice's ph runs as root (no zpr_addr in its conf => ph makes its own TUN).
declare -A SUDO=([node0]='' [ociweb]='' [alice]='sudo ' [node1]='' [vs]='' [premweb]='')

# resolve NAME -- sets N_* for the caller, or lists the valid names and exits 2.
resolve() {
  local n="${1:-}"
  if [ -z "$n" ] || [ -z "${KIND[$n]:-}" ]; then
    echo "error: unknown name: ${n:-<none>}" >&2
    echo "valid names: ${NAMES[*]}" >&2
    exit 2
  fi
  N_NAME="$n"
  N_KIND="${KIND[$n]}"; N_TARGET="${TARGET[$n]}"; N_SESSION="${SESSION[$n]}"
  N_LOG="${LOG[$n]}";   N_LAUNCH="${LAUNCH[$n]}"; N_WD="${WD[$n]}"
  N_SUDO="${SUDO[$n]}"
  # The same log as the target sees it: for docker N_LOG is this host's side of
  # the mounted volume, but a tee inside the container must write /logs/<session>
  # (deploy-docker.sh:81). For oci the two are the same path.
  [ "$N_KIND" = oci ] && N_TLOG="$N_LOG" || N_TLOG="/logs/$N_SESSION.log"
}

# oci_ip <tofu-key> -- public IP from tofu state. Memoised: one tofu call per run.
_OCI_IPS=""
oci_ip() {
  if [ -z "$_OCI_IPS" ]; then
    _OCI_IPS="$(tofu -chdir="$MULTI_DIR/oci-compute" output -json public_ips 2>/dev/null || true)"
  fi
  local ip
  ip="$(jq -r --arg k "$1" '.[$k] // empty' <<<"${_OCI_IPS:-{\}}")"
  [ -n "$ip" ] || {
    echo "error: no public IP for '$1' from tofu — is oci-compute applied?" >&2
    exit 1
  }
  printf '%s' "$ip"
}

# on NAME cmd... / on_tty NAME cmd... -- the ssh-vs-docker dispatch point.
# Args after NAME are joined into one remote shell command (they run under a
# shell on the far side, so $HOME and globs expand there).
on()     { _dispatch "" "$@"; }
on_tty() { _dispatch tty "$@"; }

_dispatch() {  # $1=tty|"" $2=NAME $3...=command
  local tty="$1" name="$2"; shift 2
  resolve "$name"
  if [ "$N_KIND" = oci ]; then
    ssh "${SSH_OPTS[@]}" ${tty:+-t} "ubuntu@$(oci_ip "$N_TARGET")" "$@"
  else
    docker exec ${tty:+-it} "$N_TARGET" bash -lc "$*"
  fi
}

# tail_log NAME <tail-args...> -- docker logs are tee'd to a host-mounted volume,
# so those need no docker at all; oci logs live on the host and go over ssh.
tail_log() {
  local n="$1"; shift
  resolve "$n"
  if [ "$N_KIND" = oci ]; then
    on "$n" "tail $* $N_LOG"          # $N_LOG holds a literal $HOME, expanded there
  else
    [ -f "$N_LOG" ] || { echo "error: no log at $N_LOG — has deploy-docker.sh run?" >&2; exit 1; }
    tail "$@" "$N_LOG"
  fi
}
