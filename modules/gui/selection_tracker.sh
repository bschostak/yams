#!/bin/bash

# Tracks checklist state updates emitted by `yad --list --row-action`.
#
# Env:
#   YAMS_STATE_FILE  File used to persist checked rows across processes.
#
# Args (appended by YAD):
#   $1 action (add|edit|del)
#   $2.. row column values (Select, Status, Package, Version, Source, Description, SourceKey)

set -euo pipefail

state_file="${YAMS_STATE_FILE:-}"
debug_log="${YAMS_DEBUG_LOG:-}"

if [[ -n "${debug_log:-}" ]]; then
  {
    printf '%s ' "$(date +'%F %T')"
    printf 'ROW_ACTION'
    printf ' %q' "$@"
    printf '\n'
  } >>"$debug_log" 2>/dev/null || true
fi

if [[ -z "$state_file" ]]; then
  exit 0
fi

first="${1:-}"

# Expected for --row-action:
#   $1 = add|edit|del, then columns...
# Some builds call CMD with only the columns; handle both.
if [[ "$first" == "add" || "$first" == "edit" || "$first" == "del" ]]; then
  action="$first"
  checked="${2:-}"
  status_icon="${3:-}"
  pkg_name="${4:-}"
  version="${5:-}"
  src_label="${6:-}"
  desc="${7:-}"
  source_key="${8:-}"
else
  action="edit"
  checked="${1:-}"
  status_icon="${2:-}"
  pkg_name="${3:-}"
  version="${4:-}"
  src_label="${5:-}"
  desc="${6:-}"
  source_key="${7:-}"
fi

# Some YAD builds may not pass hidden columns to row-action.
if [[ -z "${source_key:-}" ]]; then
  case "${src_label:-}" in
    Flatpak) source_key="flatpak" ;;
    AUR) source_key="paru" ;;
    *) source_key="pacman" ;;
  esac
fi

is_checked=false
case "$checked" in
  TRUE|true|1|yes|YES|on|ON) is_checked=true ;;
esac

if [[ -z "$pkg_name" ]]; then
  exit 0
fi

tmp="${state_file}.tmp"

mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
touch "$state_file" 2>/dev/null || true

# Remove any existing entries for this package.
# We intentionally remove by package name (not pkg+source) because some YAD builds
# don't reliably pass hidden/source columns in row-action callbacks.
awk -F'\t' -v pkg="$pkg_name" '!( $1==pkg )' "$state_file" >"$tmp" 2>/dev/null || true

# Re-add if currently checked.
if [[ "$is_checked" == true ]]; then
  printf '%s\t%s\n' "$pkg_name" "$source_key" >>"$tmp" 2>/dev/null || true
fi

# Dedupe in case multiple callbacks race.
awk -F'\t' 'NF>=1 {k=$1"\t"$2; if (!seen[k]++) print $0}' "$tmp" >"$state_file" 2>/dev/null || true
rm -f "$tmp" 2>/dev/null || true

# Row-action output: echo the row back unchanged.
# YAD expects one value per line for each column.
printf '%s\n' "${checked}" "${status_icon:-}" "${pkg_name:-}" "${version:-}" "${src_label:-}" "${desc:-}" "${source_key}"
