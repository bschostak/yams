#!/bin/bash

GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

pkg_preview_status_line() {
  local installed="$1"
  if [[ "$installed" == "yes" ]]; then
    echo -e "Status: ${GREEN}Installed${RESET}"
  else
    echo -e "Status: ${RED}Not installed${RESET}"
  fi
}

pkg_preview_pacman() {
  local mode="$1" pkg="$2"
  local tmp_inst tmp_desc installed desc

  tmp_inst="$(mktemp)" || return 1
  tmp_desc="$(mktemp)" || { rm -f "$tmp_inst"; return 1; }

  (
    if pacman -Qi "$pkg" >/dev/null 2>&1; then echo yes; else echo no; fi
  ) >"$tmp_inst" &

  (
    LC_ALL=C pacman -Si "$pkg" 2>/dev/null | awk '$0 ~ /^[[:space:]]*Description[[:space:]]*:/ { sub(/^[[:space:]]*Description[[:space:]]*:[[:space:]]*/, "", $0); print "Description: " $0; found=1; exit } END { if(!found) exit 1 }' \
    || LC_ALL=C pacman -Qi "$pkg" 2>/dev/null | awk '$0 ~ /^[[:space:]]*Description[[:space:]]*:/ { sub(/^[[:space:]]*Description[[:space:]]*:[[:space:]]*/, "", $0); print "Description: " $0; found=1; exit } END { if(!found) exit 1 }' \
    || echo "Description: No description found."
  ) >"$tmp_desc" &

  wait

  installed="$(<"$tmp_inst")"
  desc="$(<"$tmp_desc")"

  rm -f "$tmp_inst" "$tmp_desc"

  pkg_preview_status_line "$installed"
  echo "$desc"
}

pkg_preview_flatpak() {
  local mode="$1" pkg="$2"
  local appid="$pkg"

  if [[ "$appid" != *.*.* ]]; then
    local found
    found="$(flatpak search --columns=application "$appid" 2>/dev/null | awk 'NR==1{print $1}')"
    [[ -n "$found" ]] && appid="$found"
  fi

  local tmp_inst tmp_desc installed desc
  tmp_inst="$(mktemp)" || return 1
  tmp_desc="$(mktemp)" || { rm -f "$tmp_inst"; return 1; }

  (
    if flatpak list --app --columns=application 2>/dev/null | grep -Fxq "$appid"; then echo yes; else echo no; fi
  ) >"$tmp_inst" &

  (
    flatpak remote-info flathub "$appid" 2>/dev/null | awk 'NR==2{print "Description: " $0; found=1} END{ if(!found) exit 1 }' \
    || flatpak info "$appid" 2>/dev/null | awk 'NR==2{print "Description: " $0; found=1} END{ if(!found) exit 1 }' \
    || echo "Description: No description found."
  ) >"$tmp_desc" &

  wait

  installed="$(<"$tmp_inst")"
  desc="$(<"$tmp_desc")"

  rm -f "$tmp_inst" "$tmp_desc"

  pkg_preview_status_line "$installed"
  echo "$desc"
}

pkg_preview_paru() {
  local mode="$1" pkg="$2"
  local tmp_inst tmp_desc installed desc

  tmp_inst="$(mktemp)" || return 1
  tmp_desc="$(mktemp)" || { rm -f "$tmp_inst"; return 1; }

  (
    if pacman -Qm "$pkg" >/dev/null 2>&1; then echo yes; else echo no; fi
  ) >"$tmp_inst" &

  (
    LC_ALL=C paru -Si "$pkg" 2>/dev/null | awk '$0 ~ /^[[:space:]]*Description[[:space:]]*:/ { sub(/^[[:space:]]*Description[[:space:]]*:[[:space:]]*/, "", $0); print "Description: " $0; found=1; exit } END { if(!found) exit 1 }' \
    || LC_ALL=C pacman -Si "$pkg" 2>/dev/null | awk '$0 ~ /^[[:space:]]*Description[[:space:]]*:/ { sub(/^[[:space:]]*Description[[:space:]]*:[[:space:]]*/, "", $0); print "Description: " $0; found=1; exit } END { if(!found) exit 1 }' \
    || LC_ALL=C pacman -Qi "$pkg" 2>/dev/null | awk '$0 ~ /^[[:space:]]*Description[[:space:]]*:/ { sub(/^[[:space:]]*Description[[:space:]]*:[[:space:]]*/, "", $0); print "Description: " $0; found=1; exit } END { if(!found) exit 1 }' \
    || echo "Description: No description found."
  ) >"$tmp_desc" &

  wait

  installed="$(<"$tmp_inst")"
  desc="$(<"$tmp_desc")"

  rm -f "$tmp_inst" "$tmp_desc"

  pkg_preview_status_line "$installed"
  echo "$desc"
}

pkg_preview_dispatch() {
  local mode="$1" source="$2" pkg="$3"
  case "$source" in
    pacman) pkg_preview_pacman "$mode" "$pkg" ;;
    flatpak) pkg_preview_flatpak "$mode" "$pkg" ;;
    paru) pkg_preview_paru "$mode" "$pkg" ;;
    *) echo "Unknown package source." ;;
  esac
}

pkg_preview_run() {
  local arg="$1"
  local source pkg
  IFS=":" read -r source pkg <<< "$arg"
  pkg_preview_dispatch "${MODE:-install}" "$source" "$pkg"
}
