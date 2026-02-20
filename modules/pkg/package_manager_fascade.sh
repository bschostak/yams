#!/bin/bash

# Usage: ./package_manager_fascade.sh [install|remove|downgrade]
MODE="$1"

if [[ ! " install remove downgrade " =~ " $MODE " ]]; then
  echo "Usage: $0 [install|remove|downgrade]"
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$HOME/.config/bptui/config.sh"
source "$script_dir/pacman_handler.sh"
source "$script_dir/flatpak_handler.sh"
source "$script_dir/paru_handler.sh"

print_banner() {
  case "$MODE" in
    install)
      echo -e "\e[32mSelect packages to install from available sources\e[0m"
      ;;
    remove)
      echo -e "\e[32mSelect packages to remove from available sources\e[0m"
      ;;
    downgrade)
      echo -e "\e[32mSelect packages to downgrade from available sources\e[0m"
      ;;
  esac
  echo -e "\e[33mNote: Use TAB or SHIFT+TAB to select multiple packages\e[0m"
}

# The preview script
cat <<EOF > /tmp/pkg_preview.sh
#!/bin/bash
# Thin wrapper around preview_manager functions
source "$script_dir/preview_manager.sh"
pkg_preview_run "\$1"
EOF
chmod +x /tmp/pkg_preview.sh

main() {
  clear
  print_banner

  pkg_list=$(
    {
      case "$MODE" in
        install)
          $USE_PACMAN && pacman -Sl | awk '{print "pacman:" $2}'
          $USE_FLATPAK && flatpak remote-ls --app | awk '{print "flatpak:" $2}'
          $USE_PARU && paru -Sl aur | awk '{print "paru:" $2}'
          ;;
        remove)
          $USE_PACMAN && pacman -Qen | awk '{print "pacman:" $1}'
          $USE_FLATPAK && flatpak list | awk '{print "flatpak:" $2}'
          $USE_PARU && paru -Qm | awk '{print "paru:" $1}'
          ;;
        downgrade)
          $USE_PACMAN && pacman -Q | awk '{print "pacman:" $1}'
          ;;
      esac
    } | sort -u | fzf --multi --height 60% --border --preview "MODE=$MODE /tmp/pkg_preview.sh {}" --preview-window=right:60% --prompt 'Select packages: '
  )

  if [[ -z "$pkg_list" ]]; then
    echo "No packages selected."
    return
  fi

  pacman_pkgs=()
  flatpak_pkgs=()
  paru_pkgs=()
  while IFS= read -r line; do
    case "$line" in
      pacman:*) pacman_pkgs+=("${line#pacman:}") ;;
      flatpak:*) flatpak_pkgs+=("${line#flatpak:}") ;;
      paru:*) paru_pkgs+=("${line#paru:}") ;;
    esac
  done <<< "$pkg_list"

  case "$MODE" in
    install)
      if [[ ${#pacman_pkgs[@]} -gt 0 ]]; then
        clear; install_pacman_pkgs "${pacman_pkgs[@]}"; echo -e; read -p "Press any key to continue..." -n 1
      fi
      if [[ ${#flatpak_pkgs[@]} -gt 0 ]]; then
        clear; install_flatpak_pkgs "${flatpak_pkgs[@]}"; echo -e; read -p "Press any key to continue..." -n 1
      fi
      if [[ ${#paru_pkgs[@]} -gt 0 ]]; then
        clear; install_paru_pkgs "${paru_pkgs[@]}"; echo -e; read -p "Press any key to continue..." -n 1
      fi
      ;;
    remove)
      if [[ ${#pacman_pkgs[@]} -gt 0 ]]; then
        clear; remove_pacman_explicit_pkgs "${pacman_pkgs[@]}"; echo -e; read -p "Press any key to continue..." -n 1
      fi
      if [[ ${#flatpak_pkgs[@]} -gt 0 ]]; then
        clear; remove_flatpak_pkgs "${flatpak_pkgs[@]}"; echo -e; read -p "Press any key to continue..." -n 1
      fi
      if [[ ${#paru_pkgs[@]} -gt 0 ]]; then
        clear; remove_pacman_explicit_pkgs "${paru_pkgs[@]}"; echo -e; read -p "Press any key to continue..." -n 1
      fi
      ;;
    downgrade)
      if [[ ${#pacman_pkgs[@]} -gt 0 ]]; then
        clear; downgrade_pacman_packages "${pacman_pkgs[@]}"; echo -e; read -p "Press any key to continue..." -n 1
      fi
      #TODO: Add similar blocks for flatpak or paru here if handlers defined
      ;;
  esac
}

main
