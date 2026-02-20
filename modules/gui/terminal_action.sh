#!/bin/bash

set -euo pipefail

action="${1:-}"
shift || true

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

source "$repo_root/modules/config/config_controller.sh"
setup_config
source "$HOME/.config/bptui/config.sh"

source "$repo_root/modules/pkg/pacman_handler.sh"
source "$repo_root/modules/pkg/flatpak_handler.sh"
source "$repo_root/modules/pkg/paru_handler.sh"
source "$repo_root/modules/pkg/update_manager.sh"

pause() {
  echo
  read -r -n 1 -p "Press any key to close..." _ || true
}

die() {
  echo "$*" >&2
  pause
  exit 1
}

case "$action" in
  install)
    src="${1:-}"; shift || true
    case "$src" in
      pacman) install_pacman_pkgs "$@" ;;
      flatpak) install_flatpak_pkgs "$@" ;;
      paru) install_paru_pkgs "$@" ;;
      *) die "Unknown install source: $src" ;;
    esac
    pause
    ;;

  remove)
    src="${1:-}"; shift || true
    case "$src" in
      pacman) remove_pacman_explicit_pkgs "$@" ;;
      flatpak) remove_flatpak_pkgs "$@" ;;
      paru) remove_pacman_explicit_pkgs "$@" ;;
      *) die "Unknown remove source: $src" ;;
    esac
    pause
    ;;

  update)
    update_all_pkgs

    # Refresh cached catalogs used for offline searching.
    if [[ -x "$repo_root/modules/gui/cache_manager.sh" ]]; then
      echo
      echo "Refreshing local package catalogs in cache/ ..."
      "$repo_root/modules/gui/cache_manager.sh" refresh || true
    fi
    pause
    ;;

  downgrade)
    src="${1:-}"; pkg="${2:-}" ver="${3:-}"
    [[ -n "$src" && -n "$pkg" && -n "$ver" ]] || die "Usage: downgrade <pacman> <pkg> <version>"
    [[ "$src" == "pacman" ]] || die "Downgrade only implemented for pacman right now."

    command -v pkgctl >/dev/null 2>&1 || die "pkgctl is required for online downgrade downloads."

    mkdir -p "$repo_root/cache"
    echo "Downloading $pkg $ver to $repo_root/cache ..."
    pkgctl repo download "$pkg" "$ver" --dest "$repo_root/cache/"

    pkg_file="$(find "$repo_root/cache/" -type f -name "${pkg}-${ver}-*.pkg.tar.*" | head -n 1)"
    [[ -n "$pkg_file" ]] || die "Downloaded archive not found in cache/."

    echo
    echo "Downgrading $pkg to $ver ..."
    sudo pacman -U --needed "$pkg_file"

    echo
    read -r -p "Add $pkg to IgnorePkg? [y/N]: " add_ignore || true
    if [[ "$add_ignore" =~ ^[Yy]$ ]]; then
      sudo cp /etc/pacman.conf /etc/pacman.conf.bak
      if grep -q "^IgnorePkg" /etc/pacman.conf; then
        sudo sed -i "/^IgnorePkg/ s/$/ $pkg/" /etc/pacman.conf
      else
        sudo sed -i "/^#IgnorePkg/ c\\IgnorePkg=$pkg" /etc/pacman.conf
      fi
      echo "$pkg added to IgnorePkg."
    fi

    pause
    ;;

  *)
    die "Unknown action: $action"
    ;;
esac
