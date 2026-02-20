#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

source "$repo_root/modules/config/config_controller.sh"
setup_config
source "$HOME/.config/bptui/config.sh"

have() { command -v "$1" >/dev/null 2>&1; }

cache_dir="$repo_root/cache"
mkdir -p "$cache_dir"

pacman_cache="$cache_dir/pacman_repo.tsv"
paru_cache="$cache_dir/aur.tsv"
flatpak_cache="$cache_dir/flatpak_flathub.tsv"

refresh_pacman() {
	[[ "${USE_PACMAN:-false}" == true ]] || return 0
	have pacman || return 0

	local tmp
	tmp="${pacman_cache}.tmp"
	: >"$tmp"

	# Full repo catalog with descriptions.
	# '.' matches everything; this can take a bit but enables offline searching.
	LC_ALL=C pacman -Ss --color never . 2>/dev/null | awk '
		BEGIN{pkg="";ver="";desc=""}
		/^[^[:space:]]+\// {
			if (pkg!="") {print pkg"\t"ver"\t"desc}
			split($1,a,"/"); pkg=a[2]; ver=$2; desc="";
			next
		}
		/^[[:space:]]+/ {
			sub(/^[[:space:]]+/,"",$0); desc=$0; next
		}
		END{ if (pkg!="") print pkg"\t"ver"\t"desc }
	' >"$tmp" || true

	mv "$tmp" "$pacman_cache"
}

refresh_paru() {
	[[ "${USE_PARU:-false}" == true ]] || return 0
	have paru || return 0

	local tmp limit
	tmp="${paru_cache}.tmp"
	: >"$tmp"
	limit="${YAMS_CACHE_AUR_LIMIT:-5000}"

	# Best-effort AUR catalog. This can be very large; limit to keep it practical.
	LC_ALL=C paru -Ss --color never . 2>/dev/null | awk '
		BEGIN{pkg="";ver="";desc="";is_aur=0;count=0;limit=ENVIRON["LIMIT"]+0}
		/^[^[:space:]]+\// {
			if (pkg!="" && is_aur==1) {
				print pkg"\t"ver"\t"desc;
				count++;
				if (limit>0 && count>=limit) exit
			}
			split($1,a,"/"); is_aur=(a[1]=="aur")?1:0; pkg=a[2]; ver=$2; desc="";
			next
		}
		/^[[:space:]]+/ { sub(/^[[:space:]]+/,"",$0); desc=$0; next }
		END{ if (pkg!="" && is_aur==1 && (limit<=0 || count<limit)) print pkg"\t"ver"\t"desc }
	' LIMIT="$limit" >"$tmp" || true

	mv "$tmp" "$paru_cache"
}

refresh_flatpak() {
	[[ "${USE_FLATPAK:-false}" == true ]] || return 0
	have flatpak || return 0

	local tmp
	tmp="${flatpak_cache}.tmp"
	: >"$tmp"

	# Prefer flathub if present; fallback to any remote if flathub isn't configured.
	if flatpak remotes 2>/dev/null | awk '{print $1}' | grep -Fxq flathub; then
		flatpak remote-ls --app --columns=application,version,description flathub 2>/dev/null \
			| awk -F'\t' 'NF>=1 {print $1"\t"$2"\t"$3}' >"$tmp" || true
	else
		flatpak remote-ls --app --columns=application,version,description 2>/dev/null \
			| awk -F'\t' 'NF>=1 {print $1"\t"$2"\t"$3}' >"$tmp" || true
	fi

	mv "$tmp" "$flatpak_cache"
}

refresh_all() {
	refresh_pacman
	refresh_paru
	refresh_flatpak
}

cmd="${1:-}"
case "$cmd" in
	refresh)
		refresh_all
		;;
	*)
		echo "Usage: $0 refresh" >&2
		exit 2
		;;
esac
