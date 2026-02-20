#!/bin/bash

# Called by `yad --list --select-action`.
# YAD appends all column values as args.
# Columns: Select, Status, Package, Version, Source, Description, SourceKey

set -euo pipefail

action_pipe="${YAMS_ACTION_PIPE:-}"
[[ -n "$action_pipe" ]] || exit 0

state_file="${YAMS_STATE_FILE:-}"

update_state() {
	local checked="$1" pkg_name="$2" src_label="$3" src_key="$4"
	[[ -n "${state_file:-}" ]] || return 0
	[[ -n "${pkg_name:-}" ]] || return 0

	if [[ -z "${src_key:-}" ]]; then
		case "$src_label" in
			Flatpak) src_key="flatpak" ;;
			AUR) src_key="paru" ;;
			*) src_key="pacman" ;;
		esac
	fi

	local is_checked=false
	case "$checked" in
		TRUE|true|1|yes|YES|on|ON) is_checked=true ;;
	esac

	mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
	touch "$state_file" 2>/dev/null || true

	local tmp="${state_file}.tmp"
	# Remove any existing entries for this package.
	# Use pkg-only to avoid stale selections when source columns are missing.
	awk -F'\t' -v pkg="$pkg_name" '!( $1==pkg )' "$state_file" >"$tmp" 2>/dev/null || true

	if [[ "$is_checked" == true ]]; then
		printf '%s\t%s\n' "$pkg_name" "$src_key" >>"$tmp" 2>/dev/null || true
	fi

	awk -F'\t' 'NF>=1 {k=$1"\t"$2; if (!seen[k]++) print $0}' "$tmp" >"$state_file" 2>/dev/null || true
	rm -f "$tmp" 2>/dev/null || true
}

debug_log="${YAMS_DEBUG_LOG:-}"
if [[ -n "${debug_log:-}" ]]; then
	{
		printf '%s ' "$(date +'%F %T')"
		printf 'SELECT_ACTION'
		printf ' %q' "$@"
		printf '\n'
	} >>"$debug_log" 2>/dev/null || true
fi

repo_root="${YAMS_REPO_ROOT:-}"
send_action=""
if [[ -n "${repo_root:-}" ]] && [[ -x "$repo_root/modules/gui/send_action.sh" ]]; then
	send_action="$repo_root/modules/gui/send_action.sh"
fi

checked="${1:-}"
pkg="${3:-}"
src_label="${5:-}"
src_key="${7:-}"

if [[ -z "${src_key:-}" ]]; then
	case "$src_label" in
		Flatpak) src_key="flatpak" ;;
		AUR) src_key="paru" ;;
		*) src_key="pacman" ;;
	esac
fi

update_state "$checked" "$pkg" "$src_label" "$src_key"

pkg="${pkg//|/ }"
src_label="${src_label//|/ }"
src_key="${src_key//|/ }"

if [[ -n "${send_action:-}" ]]; then
	"$send_action" DETAILS "${pkg}|${src_label}|${src_key}"
else
	printf '%s\n' "DETAILS|${pkg}|${src_label}|${src_key}" >"$action_pipe"
fi
