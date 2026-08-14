#!/usr/bin/env bash

if (( $# == 0 )); then
  echo "Usage: $0 <command> [args...]" >&2
  exit 2
fi

trap 'exit 130' INT
trap 'exit 143' TERM

while true; do
  # No `clear`: that blanks the screen while the command runs, which flickers.
  # Home the cursor, overwrite in place, then erase whatever the last run left below.
  printf '\e[H'
  "$@"
  rc=$?
  printf '\e[J'

  # Avoid repeatedly printing an error when the command cannot be executed.
  case "$rc" in
    126|127) exit "$rc" ;;
  esac

  sleep "${REPEAT_INTERVAL:-1}"
done
