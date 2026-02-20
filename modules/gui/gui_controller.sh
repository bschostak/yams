#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

source "$repo_root/modules/config/config_controller.sh"
setup_config
source "$HOME/.config/bptui/config.sh"

source "$repo_root/modules/pkg/pacman_handler.sh"
source "$repo_root/modules/pkg/flatpak_handler.sh"
source "$repo_root/modules/pkg/paru_handler.sh"

# ---------- helpers ----------

yams_have() { command -v "$1" >/dev/null 2>&1; }

yams_yad_error() {
  local msg="$1"
  yad --error --title="yams" --text="$msg" 2>/dev/null || echo "$msg" >&2
}

yams_pick_terminal() {
  if [[ -n "${TERMINAL:-}" ]] && yams_have "$TERMINAL"; then
    echo "$TERMINAL"
    return 0
  fi
  if yams_have x-terminal-emulator; then echo x-terminal-emulator; return 0; fi
  if yams_have gnome-terminal; then echo gnome-terminal; return 0; fi
  if yams_have konsole; then echo konsole; return 0; fi
  if yams_have xfce4-terminal; then echo xfce4-terminal; return 0; fi
  if yams_have kitty; then echo kitty; return 0; fi
  if yams_have alacritty; then echo alacritty; return 0; fi
  if yams_have wezterm; then echo wezterm; return 0; fi
  if yams_have xterm; then echo xterm; return 0; fi
  return 1
}

yams_spawn_terminal_cmd() {
  local title="$1"
  shift
  local terminal
  terminal="$(yams_pick_terminal)" || { yams_yad_error "No terminal emulator found. Set TERMINAL env var or install xterm/gnome-terminal."; return 1; }

  local cmd=("$@")

  case "$terminal" in
    gnome-terminal)
      # Try to keep terminal open until command exits.
      (gnome-terminal --title="$title" --wait -- "${cmd[@]}") >/dev/null 2>&1 \
        || (gnome-terminal --title="$title" -- "${cmd[@]}") >/dev/null 2>&1 &
      ;;
    konsole)
      (konsole --new-tab -p tabtitle="$title" -e "${cmd[@]}") >/dev/null 2>&1 &
      ;;
    xfce4-terminal)
      (xfce4-terminal --title="$title" -e "${cmd[*]}") >/dev/null 2>&1 &
      ;;
    kitty|alacritty|wezterm|xterm|x-terminal-emulator)
      ("$terminal" -e "${cmd[@]}") >/dev/null 2>&1 &
      ;;
    *)
      ("$terminal" -e "${cmd[@]}") >/dev/null 2>&1 &
      ;;
  esac
}

yams_run_action_in_terminal() {
  local title="$1"
  shift
  local action_script="$repo_root/modules/gui/terminal_action.sh"

  if [[ ! -x "$action_script" ]]; then
    yams_yad_error "Missing executable: $action_script"
    return 1
  fi

  local cmd
  cmd="$(printf '%q' "$action_script")"
  local arg
  for arg in "$@"; do
    cmd+=" $(printf '%q' "$arg")"
  done
  yams_spawn_terminal_cmd "$title" bash -lc "$cmd"
}

yams_pkgctl_versions() {
  local pkg="$1"
  command -v pkgctl >/dev/null 2>&1 || return 0
  pkgctl repo search "$pkg" 2>/dev/null \
    | awk -F'|' 'NF>=3 {v=$3; gsub(/^[ \t]+|[ \t]+$/,"",v); if (v!="") print v}' \
    | sort -Vu
}

yams_cached_versions() {
  local pkg="$1"
  local cache_dir="$repo_root/cache"
  [[ -d "$cache_dir" ]] || return 0
  find "$cache_dir" -maxdepth 1 -type f -name "${pkg}-*.pkg.tar.*" 2>/dev/null \
    | sed -E "s#.*/${pkg}-##" \
    | sed -E 's/-[^-]+-[^-]+\.pkg\.tar\..*$//' \
    | sort -Vu
}

yams_pick_downgrade_version() {
  local pkg="$1"
  local current
  current="$(pacman -Qi "$pkg" 2>/dev/null | awk -F': ' '/^Version/ {print $2; exit}')"

  local versions
  versions="$( { yams_cached_versions "$pkg"; yams_pkgctl_versions "$pkg"; } | sort -Vu )"

  if [[ -z "${versions:-}" ]]; then
    yams_yad_error "No versions found for $pkg (need cache packages or pkgctl)."
    return 1
  fi

  # Build list input: Version\n...
  local selected
  selected="$(printf '%s\n' "$versions" | yad --list --title="Select version" --text="Package: $pkg\nCurrent: ${current:-unknown}" \
    --column="Version" --no-headers --height=400 --width=520 --print-column=1 --separator="" 2>/dev/null)"

  [[ -n "${selected:-}" ]] || return 1
  printf '%s' "$selected"
}

yams_sanitize_field() {
  local s="${1-}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\t'/ }"
  # YAD renders some text via Pango markup; escape '&' to avoid warnings.
  s="${s//&/&amp;}"
  s="${s//|/ /}"
  printf '%s' "$s"
}

yams_unquote() {
  local s="${1-}"
  # Trim whitespace
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  # Remove common surrounding quotes (YAD may shell-quote substitutions)
  if [[ "$s" == "'"*"'" ]] && [[ ${#s} -ge 2 ]]; then
    s="${s:1:${#s}-2}"
  fi
  if [[ "$s" == '"'*'"' ]] && [[ ${#s} -ge 2 ]]; then
    s="${s:1:${#s}-2}"
  fi
  # Handle escaped single-quote wrappers like \'vim\'
  if [[ "$s" == "\\'"*"\\'" ]] && [[ ${#s} -ge 4 ]]; then
    s="${s:2:${#s}-4}"
  fi
  printf '%s' "$s"
}

yams_state_get_checked() {
  local state_file="$1"
  [[ -f "$state_file" ]] || return 0
  awk -F'\t' 'NF>=1 {k=$1"\t"$2; if (!seen[k]++) print $0}' "$state_file"
}

yams_split_checked_by_source() {
  local state_file="$1"
  PACMAN_PKGS=()
  FLATPAK_PKGS=()
  PARU_PKGS=()

  while IFS=$'\t' read -r pkg src; do
    [[ -z "${pkg:-}" ]] && continue
    case "${src:-}" in
      pacman) PACMAN_PKGS+=("$pkg") ;;
      flatpak) FLATPAK_PKGS+=("$pkg") ;;
      paru) PARU_PKGS+=("$pkg") ;;
    esac
  done < <(yams_state_get_checked "$state_file")
}

# Parse pacman -Ss output into tab-separated rows: pkg\tver\tdesc
yams_pacman_search_rows() {
  local term="$1"
  LC_ALL=C pacman -Ss --color never "$term" 2>/dev/null | awk '
    BEGIN{pkg="";ver="";desc=""}
    /^[^[:space:]]+\// {
      # Flush previous
      if (pkg!="") {print pkg"\t"ver"\t"desc}
      split($1,a,"/"); pkg=a[2]; ver=$2; desc="";
      next
    }
    /^[[:space:]]+/ {
      sub(/^[[:space:]]+/,"",$0); desc=$0; next
    }
    END{ if (pkg!="") print pkg"\t"ver"\t"desc }
  '
}

# Parse paru -Ss output, keep only aur/* rows: pkg\tver\tdesc
yams_paru_search_rows() {
  local term="$1"
  LC_ALL=C paru -Ss --color never "$term" 2>/dev/null | awk '
    BEGIN{pkg="";ver="";desc="";is_aur=0}
    /^[^[:space:]]+\// {
      if (pkg!="" && is_aur==1) {print pkg"\t"ver"\t"desc}
      split($1,a,"/");
      is_aur = (a[1]=="aur") ? 1 : 0;
      pkg=a[2]; ver=$2; desc="";
      next
    }
    /^[[:space:]]+/ {
      sub(/^[[:space:]]+/,"",$0); desc=$0; next
    }
    END{ if (pkg!="" && is_aur==1) print pkg"\t"ver"\t"desc }
  '
}

yams_installed_pacman_rows() {
  # pkg\tver\tdesc
  LC_ALL=C pacman -Qi 2>/dev/null | awk -v RS='' -F'\n' '
    {
      name=""; ver=""; desc="";
      for (i=1;i<=NF;i++) {
        line=$i
        if (line ~ /^Name[[:space:]]*:/) { sub(/^Name[[:space:]]*:[[:space:]]*/,"",line); name=line }
        if (line ~ /^Version[[:space:]]*:/) { sub(/^Version[[:space:]]*:[[:space:]]*/,"",line); ver=line }
        if (line ~ /^Description[[:space:]]*:/) { sub(/^Description[[:space:]]*:[[:space:]]*/,"",line); desc=line }
      }
      if (name!="") print name"\t"ver"\t"desc;
    }
  '
}

yams_installed_flatpak_rows() {
  # appid\tver\tdesc
  flatpak list --app --columns=application,version,description 2>/dev/null \
    | awk -F'\t' 'NF>=1 {print $1"\t"$2"\t"$3}' \
    || true
}

yams_is_pacman_installed() { pacman -Q "$1" >/dev/null 2>&1; }
yams_is_flatpak_installed() { flatpak list --app --columns=application 2>/dev/null | grep -Fxq "$1"; }
yams_is_paru_installed() { pacman -Qm "$1" >/dev/null 2>&1; }

yams_write_list_row() {
  local list_fd="$1"
  local checked="$2" icon="$3" pkg="$4" ver="$5" src_label="$6" desc="$7" src_key="$8"
  checked="$(yams_sanitize_field "$checked")"
  icon="$(yams_sanitize_field "$icon")"
  pkg="$(yams_sanitize_field "$pkg")"
  ver="$(yams_sanitize_field "$ver")"
  src_label="$(yams_sanitize_field "$src_label")"
  desc="$(yams_sanitize_field "$desc")"
  src_key="$(yams_sanitize_field "$src_key")"
  # Feed YAD list via stdin: one value per line.
  # For 7 columns, provide 7 newline-separated values per row.
  printf '%s\n' "$checked" "$icon" "$pkg" "$ver" "$src_label" "$desc" "$src_key" >&"$list_fd"
}

yams_list_clear() {
  local list_fd="$1"
  printf '\f\n' >&"$list_fd"
}

yams_emit_installed_rows() {
  local state_file="$1"
  : >"$state_file" 2>/dev/null || true

  local -A aur_map=()
  if [[ "${USE_PARU:-false}" == true ]] && yams_have pacman; then
    while read -r n _; do
      [[ -n "${n:-}" ]] && aur_map["$n"]=1
    done < <(pacman -Qm 2>/dev/null || true)
  fi

  if [[ "${USE_PACMAN:-false}" == true ]] && yams_have pacman; then
    while IFS=$'\t' read -r pkg ver desc; do
      [[ -z "${pkg:-}" ]] && continue
      local src_label="Repo" src_key="pacman"
      if [[ -n "${aur_map[$pkg]+x}" ]]; then
        src_label="AUR"; src_key="paru"
      fi
      yams_write_list_row 1 FALSE gtk-apply "$pkg" "$ver" "$src_label" "$desc" "$src_key"
    done < <(yams_installed_pacman_rows)
  fi

  if [[ "${USE_FLATPAK:-false}" == true ]] && yams_have flatpak; then
    while IFS=$'\t' read -r appid ver desc; do
      [[ -z "${appid:-}" ]] && continue
      yams_write_list_row 1 FALSE gtk-apply "$appid" "$ver" "Flatpak" "$desc" flatpak
    done < <(yams_installed_flatpak_rows)
  fi
}

yams_emit_search_rows() {
  local state_file="$1" term="$2"
  : >"$state_file" 2>/dev/null || true

  if [[ -z "${term// }" ]]; then
    yams_emit_installed_rows "$state_file"
    return 0
  fi

  # Build installed sets once; calling `pacman -Q` per row is extremely slow.
  local -A repo_installed=() aur_installed=() flatpak_installed=()
  if [[ "${USE_PACMAN:-false}" == true ]] && yams_have pacman; then
    while IFS= read -r n; do
      [[ -n "${n:-}" ]] && repo_installed["$n"]=1
    done < <(pacman -Qq 2>/dev/null || true)

    while IFS= read -r n; do
      [[ -n "${n:-}" ]] && aur_installed["$n"]=1
    done < <(pacman -Qmq 2>/dev/null || true)
  fi

  if [[ "${USE_FLATPAK:-false}" == true ]] && yams_have flatpak; then
    while IFS= read -r appid; do
      [[ -n "${appid:-}" ]] && flatpak_installed["$appid"]=1
    done < <(flatpak list --app --columns=application 2>/dev/null || true)
  fi

  if [[ "${USE_PACMAN:-false}" == true ]] && yams_have pacman; then
    local max_pacman_results=300
    local pacman_count=0
    while IFS=$'\t' read -r pkg ver desc; do
      [[ -z "${pkg:-}" ]] && continue
      local icon="gtk-add"
      if [[ -n "${repo_installed[$pkg]+x}" ]]; then icon="gtk-apply"; fi
      yams_write_list_row 1 FALSE "$icon" "$pkg" "$ver" "Repo" "$desc" pacman
      ((pacman_count++))
      if (( pacman_count >= max_pacman_results )); then
        break
      fi
    done < <(yams_pacman_search_rows "$term")
  fi

  if [[ "${USE_PARU:-false}" == true ]] && yams_have paru; then
    local max_paru_results=100
    local paru_count=0
    while IFS=$'\t' read -r pkg ver desc; do
      [[ -z "${pkg:-}" ]] && continue
      local icon="gtk-add"
      if [[ -n "${aur_installed[$pkg]+x}" ]]; then icon="gtk-apply"; fi
      yams_write_list_row 1 FALSE "$icon" "$pkg" "$ver" "AUR" "$desc" paru
      ((paru_count++))
      if (( paru_count >= max_paru_results )); then
        break
      fi
    done < <(yams_paru_search_rows "$term")
  fi

  if [[ "${USE_FLATPAK:-false}" == true ]] && yams_have flatpak; then
    { flatpak search --columns=application,version,description "$term" 2>/dev/null || true; } \
      | awk -F'\t' 'NF>=1 && $1!~/^Application/ {print $1"\t"$2"\t"$3}' \
      | while IFS=$'\t' read -r appid ver desc; do
          [[ -z "${appid:-}" ]] && continue
          local icon="gtk-add"
          if [[ -n "${flatpak_installed[$appid]+x}" ]]; then icon="gtk-apply"; fi
          yams_write_list_row 1 FALSE "$icon" "$appid" "$ver" "Flatpak" "$desc" flatpak
        done
  fi
}

 yams_populate_list_installed() {
  local list_fd="$1" state_file="$2"
  : >"$state_file" || true
  yams_list_clear "$list_fd"

  local -A aur_map=()
  if [[ "${USE_PARU:-false}" == true ]] && yams_have pacman; then
    while read -r n _; do
      [[ -n "${n:-}" ]] && aur_map["$n"]=1
    done < <(pacman -Qm 2>/dev/null || true)
  fi

  if [[ "${USE_PACMAN:-false}" == true ]] && yams_have pacman; then
    while IFS=$'\t' read -r pkg ver desc; do
      [[ -z "${pkg:-}" ]] && continue
      local src_label="Repo" src_key="pacman"
      if [[ -n "${aur_map[$pkg]+x}" ]]; then
        src_label="AUR"; src_key="paru"
      fi
      yams_write_list_row "$list_fd" FALSE gtk-apply "$pkg" "$ver" "$src_label" "$desc" "$src_key"
    done < <(yams_installed_pacman_rows)
  fi

  if [[ "${USE_FLATPAK:-false}" == true ]] && yams_have flatpak; then
    while IFS=$'\t' read -r appid ver desc; do
      [[ -z "${appid:-}" ]] && continue
      yams_write_list_row "$list_fd" FALSE gtk-apply "$appid" "$ver" "Flatpak" "$desc" flatpak
    done < <(yams_installed_flatpak_rows)
  fi
}

yams_populate_list_search() {
  local list_fd="$1" state_file="$2" term="$3"
  : >"$state_file" || true
  yams_list_clear "$list_fd"

  if [[ -z "${term// }" ]]; then
    yams_populate_list_installed "$list_fd" "$state_file"
    return
  fi

  local cache_dir="$repo_root/cache"
  local pacman_cache="$cache_dir/pacman_repo.tsv"
  local aur_cache="$cache_dir/aur.tsv"
  local flatpak_cache="$cache_dir/flatpak_flathub.tsv"

  local -A repo_installed=() aur_installed=() flatpak_installed=()
  if yams_have pacman; then
    while IFS= read -r n; do [[ -n "${n:-}" ]] && repo_installed["$n"]=1; done < <(pacman -Qq 2>/dev/null || true)
    while IFS= read -r n; do [[ -n "${n:-}" ]] && aur_installed["$n"]=1; done < <(pacman -Qmq 2>/dev/null || true)
  fi
  if yams_have flatpak; then
    while IFS= read -r appid; do [[ -n "${appid:-}" ]] && flatpak_installed["$appid"]=1; done < <(flatpak list --app --columns=application 2>/dev/null || true)
  fi

  if [[ "${USE_PACMAN:-false}" == true ]] && yams_have pacman; then
    if [[ -f "$pacman_cache" ]]; then
      awk -F'\t' -v q="$term" 'BEGIN{q=tolower(q)} NF>=1 {p=tolower($1); d=tolower($3); if (index(p,q) || index(d,q)) print $0}' "$pacman_cache" \
        | while IFS=$'\t' read -r pkg ver desc; do
            [[ -z "${pkg:-}" ]] && continue
            local icon="gtk-add"
            if [[ -n "${repo_installed[$pkg]+x}" ]]; then icon="gtk-apply"; fi
            yams_write_list_row "$list_fd" FALSE "$icon" "$pkg" "$ver" "Repo" "$desc" pacman
          done
    else
      while IFS=$'\t' read -r pkg ver desc; do
        [[ -z "${pkg:-}" ]] && continue
        local icon="gtk-add"
        if [[ -n "${repo_installed[$pkg]+x}" ]]; then icon="gtk-apply"; fi
        yams_write_list_row "$list_fd" FALSE "$icon" "$pkg" "$ver" "Repo" "$desc" pacman
      done < <(yams_pacman_search_rows "$term")
    fi
  fi

  if [[ "${USE_PARU:-false}" == true ]] && yams_have paru; then
    if [[ -f "$aur_cache" ]]; then
      awk -F'\t' -v q="$term" 'BEGIN{q=tolower(q)} NF>=1 {p=tolower($1); d=tolower($3); if (index(p,q) || index(d,q)) print $0}' "$aur_cache" \
        | while IFS=$'\t' read -r pkg ver desc; do
            [[ -z "${pkg:-}" ]] && continue
            local icon="gtk-add"
            if [[ -n "${aur_installed[$pkg]+x}" ]]; then icon="gtk-apply"; fi
            yams_write_list_row "$list_fd" FALSE "$icon" "$pkg" "$ver" "AUR" "$desc" paru
          done
    else
      while IFS=$'\t' read -r pkg ver desc; do
        [[ -z "${pkg:-}" ]] && continue
        local icon="gtk-add"
        if [[ -n "${aur_installed[$pkg]+x}" ]]; then icon="gtk-apply"; fi
        yams_write_list_row "$list_fd" FALSE "$icon" "$pkg" "$ver" "AUR" "$desc" paru
      done < <(yams_paru_search_rows "$term")
    fi
  fi

  if [[ "${USE_FLATPAK:-false}" == true ]] && yams_have flatpak; then
    if [[ -f "$flatpak_cache" ]]; then
      awk -F'\t' -v q="$term" 'BEGIN{q=tolower(q)} NF>=1 {p=tolower($1); d=tolower($3); if (index(p,q) || index(d,q)) print $0}' "$flatpak_cache" \
        | while IFS=$'\t' read -r appid ver desc; do
            [[ -z "${appid:-}" ]] && continue
            local icon="gtk-add"
            if [[ -n "${flatpak_installed[$appid]+x}" ]]; then icon="gtk-apply"; fi
            yams_write_list_row "$list_fd" FALSE "$icon" "$appid" "$ver" "Flatpak" "$desc" flatpak
          done
    else
      { flatpak search --columns=application,version,description "$term" 2>/dev/null || true; } \
        | awk -F'\t' 'NF>=1 && $1!~/^Application/ {print $1"\t"$2"\t"$3}' \
        | while IFS=$'\t' read -r appid ver desc; do
            [[ -z "${appid:-}" ]] && continue
            local icon="gtk-add"
            if [[ -n "${flatpak_installed[$appid]+x}" ]]; then icon="gtk-apply"; fi
            yams_write_list_row "$list_fd" FALSE "$icon" "$appid" "$ver" "Flatpak" "$desc" flatpak
          done
    fi
  fi
}

yams_show_details() {
  local info_fd="$1" pkg="$2" src_label="$3" src_key="$4"
  {
    printf '\f\n'
    echo "DETAILS FOR: $pkg"
    echo "SOURCE: $src_label"
    echo "--------------------------"
    case "$src_key" in
      pacman)
        pacman -Qi "$pkg" 2>/dev/null || pacman -Si "$pkg" 2>/dev/null || echo "No pacman info."
        ;;
      flatpak)
        flatpak info "$pkg" 2>/dev/null || flatpak remote-info flathub "$pkg" 2>/dev/null || echo "No flatpak info."
        ;;
      paru)
        paru -Qi "$pkg" 2>/dev/null || paru -Si "$pkg" 2>/dev/null || pacman -Qi "$pkg" 2>/dev/null || echo "No AUR info."
        ;;
      *)
        echo "Unknown source."
        ;;
    esac
  } >&"$info_fd"
}

yams_action_loop() {
  local action_pipe="$1" key="$2" info_pipe="$3" state_file="$4" list_pipe="$5"

  # This loop should never crash the whole GUI.
  # External tools (pacman/flatpak/paru/pkgctl) may exit non-zero in normal situations.
  set +e

  local debug_log="${YAMS_DEBUG_LOG:-}"

  # Keep the FIFO open even when no writers are connected.
  exec 7<>"$action_pipe"

  # Open writers (blocks until readers are up).
  exec 9>"$info_pipe"

  # Start persistent list plug once; we'll update it by writing to list_pipe.
  yad --plug="$key" --tabnum=2 --list --checklist --listen \
      --column="Select:CHK" --column="Status:IMG" --column="Package" --column="Version" --column="Source" --column="Description" --column="SourceKey" \
      --hide-column=7 --search-column=3 --expand-column=6 --ellipsize=end --grid-lines=both --editable-cols=1 \
      --row-action="$repo_root/modules/gui/selection_tracker.sh" \
      --select-action="$repo_root/modules/gui/list_select_to_action.sh" \
      <"$list_pipe" &
  local list_pid=$!

  # Keep list FIFO open so the list plug doesn't exit on EOF.
  # Important: opening a FIFO for write blocks until a reader is connected.
  # Start the list plug first (reader), then open the writer.
  exec 8>"$list_pipe"
  if [[ -n "${debug_log:-}" ]]; then
    printf '%s LIST_PID started %s\n' "$(date +'%F %T')" "$list_pid" >>"$debug_log" 2>/dev/null || true
  fi

  # Initial list.
  if [[ -n "${debug_log:-}" ]]; then
    printf '%s START_LIST installed %q\n' "$(date +'%F %T')" "" >>"$debug_log" 2>/dev/null || true
  fi
  yams_populate_list_installed 8 "$state_file" || true

  while IFS= read -r line <&7; do
    [[ -z "${line:-}" ]] && continue

    if [[ -n "${debug_log:-}" ]]; then
      printf '%s RECV %s\n' "$(date +'%F %T')" "$line" >>"$debug_log" 2>/dev/null || true
    fi

    local action payload
    if [[ "$line" == *'|'* ]]; then
      action="${line%%|*}"
      payload="${line#*|}"
    else
      action="$line"
      payload=""
    fi

    case "$action" in
      SEARCH)
        local term
        term="$(yams_unquote "$payload")"
        if [[ -n "${debug_log:-}" ]]; then
          printf '%s START_LIST search %q\n' "$(date +'%F %T')" "$term" >>"$debug_log" 2>/dev/null || true
        fi
        if [[ -z "${term// }" ]]; then
          yams_populate_list_installed 8 "$state_file" || true
        else
          yams_populate_list_search 8 "$state_file" "$term" || true
        fi
        ;;
      INSTALL)
        yams_split_checked_by_source "$state_file"
        if [[ ${#PACMAN_PKGS[@]} -eq 0 && ${#FLATPAK_PKGS[@]} -eq 0 && ${#PARU_PKGS[@]} -eq 0 ]]; then
          yams_yad_error "No packages selected. Tick a checkbox first."
          continue
        fi
        if [[ ${#PACMAN_PKGS[@]} -gt 0 ]]; then yams_run_action_in_terminal "Install (pacman)" install pacman "${PACMAN_PKGS[@]}" || true; fi
        if [[ ${#FLATPAK_PKGS[@]} -gt 0 ]]; then yams_run_action_in_terminal "Install (flatpak)" install flatpak "${FLATPAK_PKGS[@]}" || true; fi
        if [[ ${#PARU_PKGS[@]} -gt 0 ]]; then yams_run_action_in_terminal "Install (paru)" install paru "${PARU_PKGS[@]}" || true; fi
        ;;
      REMOVE)
        yams_split_checked_by_source "$state_file"
        if [[ ${#PACMAN_PKGS[@]} -eq 0 && ${#FLATPAK_PKGS[@]} -eq 0 && ${#PARU_PKGS[@]} -eq 0 ]]; then
          yams_yad_error "No packages selected. Tick a checkbox first."
          continue
        fi
        if [[ ${#PACMAN_PKGS[@]} -gt 0 ]]; then yams_run_action_in_terminal "Remove (pacman)" remove pacman "${PACMAN_PKGS[@]}" || true; fi
        if [[ ${#FLATPAK_PKGS[@]} -gt 0 ]]; then yams_run_action_in_terminal "Remove (flatpak)" remove flatpak "${FLATPAK_PKGS[@]}" || true; fi
        if [[ ${#PARU_PKGS[@]} -gt 0 ]]; then yams_run_action_in_terminal "Remove (paru)" remove paru "${PARU_PKGS[@]}" || true; fi
        ;;
      DOWNGRADE)
        yams_split_checked_by_source "$state_file"
        if [[ ${#PACMAN_PKGS[@]} -eq 0 ]]; then
          yams_yad_error "No pacman packages selected for downgrade."
          continue
        fi
        if [[ ${#PACMAN_PKGS[@]} -gt 0 ]]; then
          for pkg in "${PACMAN_PKGS[@]}"; do
            if ! command -v pkgctl >/dev/null 2>&1; then
              yams_yad_error "pkgctl is required for downgrade downloads."
              break
            fi
            local ver
            ver="$(yams_pick_downgrade_version "$pkg" || true)"
            [[ -n "${ver:-}" ]] || continue
            yams_run_action_in_terminal "Downgrade ($pkg)" downgrade pacman "$pkg" "$ver" || true
          done
        fi
        ;;
      UPDATE)
        yams_run_action_in_terminal "Update" update || true
        ;;
      DETAILS)
        # payload: pkg|sourceLabel|sourceKey
        local p s_label s_key
        p="${payload%%|*}"
        local rest="${payload#*|}"
        s_label="${rest%%|*}"
        s_key="${rest#*|}"
        yams_show_details 9 "$p" "$s_label" "$s_key" || true
        ;;
    esac
  done
}

yams_gui_run() {
  if ! yams_have yad; then
    echo "yad is required. Install it (e.g. 'sudo pacman -S yad')." >&2
    return 1
  fi

  # Ensure offline search catalogs exist (best-effort).
  if [[ -x "$repo_root/modules/gui/cache_manager.sh" ]]; then
    "$repo_root/modules/gui/cache_manager.sh" refresh >/dev/null 2>&1 || true
  fi

  local runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
  local base="${runtime_dir}/yams_${UID}_$RANDOM"
  local action_pipe="${base}_action"
  local info_pipe="${base}_info"
  local list_pipe="${base}_list"
  local state_file="${base}_state.tsv"

  mkfifo "$action_pipe" "$info_pipe" "$list_pipe"

  export YAMS_ACTION_PIPE="$action_pipe"
  export YAMS_INFO_PIPE="$info_pipe"
  export YAMS_STATE_FILE="$state_file"
  export YAMS_LIST_PIPE="$list_pipe"
  export YAMS_REPO_ROOT="$repo_root"
  export YAMS_DEBUG_LOG="${XDG_RUNTIME_DIR:-/tmp}/yams_gui_${UID}.log"

  {
    printf '%s STARTUP action_pipe=%q info_pipe=%q list_pipe=%q state_file=%q\n' "$(date +'%F %T')" "$action_pipe" "$info_pipe" "$list_pipe" "$state_file"
  } >>"$YAMS_DEBUG_LOG" 2>/dev/null || true

  local key="$$"
  local info_pid="" bar_pid="" action_pid=""

  cleanup() {
    local pid
    for pid in ${bar_pid-} ${action_pid-} ${info_pid-}; do
      [[ -n "${pid:-}" ]] && kill "$pid" 2>/dev/null || true
    done

    # Best-effort kill all yad children.
    pkill -P $$ yad 2>/dev/null || true

    local f
    for f in "${action_pipe-}" "${info_pipe-}" "${list_pipe-}" "${state_file-}"; do
      [[ -n "${f:-}" ]] && rm -f "$f" 2>/dev/null || true
    done
  }
  trap cleanup EXIT INT TERM

  # Start info pane: it listens to $info_pipe and updates display.
  (cat "$info_pipe" | yad --plug="$key" --tabnum=3 --text-info --listen --fontname="Monospace 10") &
  info_pid=$!

  # Start background action handler (manages list plug lifecycle too).
  yams_action_loop "$action_pipe" "$key" "$info_pipe" "$state_file" "$list_pipe" &
  action_pid=$!

  # Action bar plug. %1 is the Search field.
  yad --plug="$key" --tabnum=1 --form --columns=6 \
    --field="Search:CE" "" \
    --field="Search:FBTN" "\"$repo_root/modules/gui/send_action.sh\" SEARCH %1" \
    --field="Update!gtk-refresh:FBTN" "\"$repo_root/modules/gui/send_action.sh\" UPDATE" \
    --field="Install!gtk-add:FBTN" "\"$repo_root/modules/gui/send_action.sh\" INSTALL" \
    --field="Remove!gtk-remove:FBTN" "\"$repo_root/modules/gui/send_action.sh\" REMOVE" \
    --field="Downgrade!gtk-undo:FBTN" "\"$repo_root/modules/gui/send_action.sh\" DOWNGRADE" &
  bar_pid=$!

  # Container window.
  yad --paned --key="$key" --title="YAD Application Management Software" \
    --width=1000 --height=850 --orient=vertical \
    --menu="File|Quit!quit" \
    --button="Exit!gtk-quit:1" || true

  # Cleanup is handled by trap.
}
