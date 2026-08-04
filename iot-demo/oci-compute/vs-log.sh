#!/usr/bin/env bash
# Follow a ZPR service's journal on zpr-core, live and readable:
#   - new lines only (no history dump)
#   - strips journald's prefix AND the vs app's own ISO timestamp (everything
#     before the log level)
#   - colorizes the level (INFO green, WARN yellow, ERROR red)
#
# Usage:  ./vs-log.sh [unit]        # unit defaults to zpr-vs
# Examples:
#   ./vs-log.sh                     # follow zpr-vs
#   ./vs-log.sh zpr-egress          # follow the egress adapter
#   ./vs-log.sh zpr-node            # follow the node
#
# Uses $CORE if exported, otherwise reads zpr-core's public IP from tofu.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT="${1:-zpr-vs}"
KEY="${SSH_KEY:-$HOME/.ssh/zpr-demo}"

CORE="${CORE:-$(tofu -chdir="$HERE" output -raw zpr_core_public_ip 2>/dev/null)}"
[ -n "$CORE" ] || {
  echo "ERROR: could not determine zpr-core IP. Export \$CORE, or run from a dir" >&2
  echo "       with applied oci-compute state so 'tofu output' can resolve it." >&2
  exit 1
}

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "opc@$CORE" \
  "sudo journalctl -u $UNIT -f -n 0 -o cat" \
| sed -u -E 's/.*(INFO|WARN|ERROR|DEBUG|TRACE)/\1/' \
| sed -u -E $'s/^INFO/\033[32mINFO\033[0m/; s/^WARN/\033[33mWARN\033[0m/; s/^ERROR/\033[31mERROR\033[0m/'
