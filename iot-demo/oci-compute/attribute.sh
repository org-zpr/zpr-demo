#!/usr/bin/env bash
# Edit the visa service's attribute file on zpr-core and flush the vs cache.
#
#   ./attribute.sh set <actor> <attr> <value>   # attr -> ["value"]; adds if absent
#   ./attribute.sh del <actor> <attr>           # drop attr; actor entry stays as {}
#   ./attribute.sh show [actor]                 # print the remote file, or one entry
#   ./attribute.sh push                         # overwrite remote with setup/attrfile.json
#   ./attribute.sh selftest                     # offline jq-transform check
#
# Edits happen in place on the instance, so the git tree stays clean and
# setup/attrfile.json remains the baseline that `tofu apply` re-uploads.
# jq runs LOCALLY (read over SSH -> transform -> write over SSH) so the OL9 image
# needs no extra package.
#
# ponytail: read-modify-write over SSH is not atomic. Fine for a single-operator
# demo; if concurrent edits ever matter, move the jq onto the instance under flock.
set -euo pipefail

command -v jq >/dev/null || { echo "error: jq is required (it runs locally, not on the instance)" >&2; exit 1; }

usage() { grep '^#   \./' "$0" >&2; exit 1; }

# --- the transforms: the only non-trivial logic, pinned down by selftest ---
jq_set() { jq --arg a "$1" --arg k "$2" --arg v "$3" '.[$a][$k] = [$v]'; }
jq_del() { jq --arg a "$1" --arg k "$2" 'del(.[$a][$k])'; }

canon() { jq -S -c .; }   # canonical form: the remote file is hand-formatted, so a
                          # byte compare would report spurious changes.

# --- selftest: the exact four-step scenario from the feature spec, offline ---
selftest() {
  local base s1 s2 s3 s4 ok=0
  base='{"device-a.zpr.org":{"OCIApproved":["true"]},"device-b.zpr.org":{"OCIApproved":["true"]},"egress.zpr.org" : {"OCIApproved":["true"]}}'
  chk() { # <label> <got> <want>
    local g w
    g=$(canon <<<"$2"); w=$(canon <<<"$3")
    [ "$g" = "$w" ] || { echo "FAIL $1"$'\n'"  got  $g"$'\n'"  want $w" >&2; ok=1; return; }
    echo "ok  $1"
  }

  s1=$(jq_set device-a.zpr.org OCIApproved true <<<"$base")
  chk "set to the value already there changes nothing" "$s1" "$base"

  s2=$(jq_del device-a.zpr.org OCIApproved <<<"$s1")
  chk "del drops the attr, leaves the actor entry" "$s2" \
    '{"device-a.zpr.org":{},"device-b.zpr.org":{"OCIApproved":["true"]},"egress.zpr.org":{"OCIApproved":["true"]}}'

  s3=$(jq_set device-a.zpr.org OCIApproved foo <<<"$s2")
  chk "set re-adds a missing attr" "$s3" \
    '{"device-a.zpr.org":{"OCIApproved":["foo"]},"device-b.zpr.org":{"OCIApproved":["true"]},"egress.zpr.org":{"OCIApproved":["true"]}}'

  s4=$(jq_set device-a.zpr.org OCIApproved true <<<"$s3")
  chk "set replaces an existing value" "$s4" "$base"

  chk "del of an absent attr is a no-op" "$(jq_del device-b.zpr.org Nope <<<"$base")" "$base"
  return $ok
}

cmd="${1:-}"; shift || true
[ "$cmd" = selftest ] && { selftest; exit; }
case "$cmd" in set|del|show|push) ;; *) usage ;; esac   # before lib.sh: it costs tofu calls

source "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
REMOTE="$ZPR_DIR/vs/attrfile.json"
LOCAL="$HERE/../setup/attrfile.json"

read_remote()  { ssh_core "sudo cat $REMOTE"; }
write_remote() { ssh_core "sudo tee $REMOTE >/dev/null"; }

# Flush after the write. vs-admin runs first so a failed flush aborts (set -e) instead
# of printing success; the printed order still matches the spec.
flush() {
  local out
  out=$("$HERE/vs-admin.sh" services -i attrfile --flush)
  echo "-> flushed visa service cache"
  printf '%s\n' "$out" | sed 's/^/-> /'
}

# apply <transform-fn> <actor> <args...>
apply() {
  local fn="$1" actor="$2" before after
  shift
  before=$(read_remote)
  jq -e --arg a "$actor" 'has($a)' >/dev/null <<<"$before" || {
    echo "error: no such actor: $actor -- known: $(jq -r 'keys|join(", ")' <<<"$before")" >&2
    exit 1
  }
  after=$("$fn" "$@" <<<"$before")
  [ "$(canon <<<"$before")" = "$(canon <<<"$after")" ] && { echo "-> no change"; exit 0; }
  jq . <<<"$after" | write_remote
  echo "-> updated trusted service backing file"
  flush
}

case "$cmd" in
  set)  [ $# -eq 3 ] || usage; apply jq_set "$@" ;;
  del)  [ $# -eq 2 ] || usage; apply jq_del "$@" ;;
  show) if [ $# -eq 1 ]; then read_remote | jq --arg a "$1" '.[$a]'; else read_remote | jq .; fi ;;
  push) jq empty "$LOCAL"
        write_remote < "$LOCAL"
        echo "-> pushed $LOCAL to zpr-core:$REMOTE"
        flush ;;
  *)    usage ;;
esac
