#!/bin/bash

set -euo pipefail

action="${1:-}"
shift || true

action_pipe="${YAMS_ACTION_PIPE:-}"
debug_log="${YAMS_DEBUG_LOG:-}"

if [[ -n "${debug_log:-}" ]]; then
  {
    printf '%s ' "$(date +'%F %T')"
    printf 'SEND %q' "$action"
    if [[ "$#" -gt 0 ]]; then
      printf ' '
      printf '%q ' "$@"
    fi
    printf '\n'
  } >>"$debug_log" 2>/dev/null || true
fi

[[ -n "${action_pipe:-}" ]] || exit 0

sanitize() {
  local s="$1"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  printf '%s' "$s"
}

sanitize_action() {
  local s
  s="$(sanitize "$1")"
  s="${s//|/ }"
  printf '%s' "$s"
}

sanitize_payload() {
  # Payloads may legitimately contain '|', so only strip newlines/CR.
  sanitize "$1"
}

action="$(sanitize_action "$action")"

if [[ "$#" -gt 0 ]]; then
  payload="$(sanitize_payload "$*")"
  printf '%s\n' "${action}|${payload}" >"$action_pipe"
else
  printf '%s\n' "$action" >"$action_pipe"
fi
