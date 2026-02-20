#!/bin/bash

function install_pacman_pkgs() {
  packages=("$@")

  if [[ -n "${packages[*]}" ]]; then
    echo "Installing selected pkgs: ${packages[*]}"
    echo -e
    sudo pacman -S --needed "${packages[@]}" || echo "Some packages may not be available."
  else
    echo "No packages selected."
  fi
}

function remove_pacman_explicit_pkgs() {
  packages=("$@")

  if [[ -n "${packages[*]}" ]]; then
    echo "Removing selected pkgs: '${packages[*]}'"
    echo -e
    sudo pacman -Rns -- "${packages[@]}" || echo "Some packages may not be available."
  else
    echo "No packages selected."
  fi
}

function remove_pacman_all_pkgs() {
  clear

  echo -e "\e[32mSelect packages to remove\e[0m"
  echo -e "\e[33mNote: To select multiple packages use SHIFT+TAB\e[0m"

  packages=$(pacman -Q | awk '{print $1}' | fzf --multi --height 50% --border --prompt "Select packages: ")

  if [[ -n "$packages" ]]; then
    echo "Removing selected pkgs: '${packages[*]}'"
    echo -e
    sudo pacman -Rns $(echo "$packages" | tr '\n' ' ') || echo "Some packages may not be available."
  else
    echo "No packages selected."
  fi
  echo -e
  read -p "Press any key to continue..." -n 1
}

function update_pacman_pkgs() {
  echo -e
  echo -e "\e[33mUpdating repo packages...\e[0m"
  echo -e

  sudo pacman -Syu

  echo -e "\e[32mRepo packages updated.\e[0m"
  echo -e
}

function clean_pacman_cache() {
  clear

  echo -e
  echo "Cleaning pacman cache..."
  echo -e

  sudo pacman -Scc

  echo "Cache cleaned."

  clear
}

function remove_orphan_packages() {
  clear
  echo -e
  echo "Removing orphan packages..."
  echo -e

  sudo pacman -Rns $(pacman -Qtdq)

  echo "Orphan packages removed."

  clear
}


# Downgrade a single package, with cache and online lookup, prompt for ignore
downgrade_single_pacman_package() {
  local pkg="$1"
  local online_versions selected_version pkg_file current_version

  # Only lookup online versions (requires pkgctl)
  if ! command -v pkgctl &>/dev/null; then
    echo -e "\e[31mpkgctl is required for online lookup.\e[0m"
    return
  fi

  online_versions=$(pkgctl repo search "$pkg" | awk -F'|' '/^AUR/ {print $3}' | sort -V)

  if [[ -z "$online_versions" ]]; then
    echo -e "\e[31mNo online versions found for $pkg\e[0m"
    return
  fi

  current_version=$(pacman -Qi "$pkg" 2>/dev/null | awk -F': ' '/Version/ {print $2}')

  selected_version=$(echo "$online_versions" | fzf --height 30% --border --prompt "[$pkg] Current: $current_version | Select online version: ")

  if [[ -z "$selected_version" ]]; then
    echo "No version selected for $pkg. Skipping."
    return
  fi

  # Download the package archive to cache/
  mkdir -p "cache"
  echo "Downloading $pkg $selected_version to cache/ ..."
  pkgctl repo download "$pkg" "$selected_version" --dest "cache/"

  # Find the downloaded archive in cache/
  pkg_file=$(find "cache/" -type f -name "${pkg}-${selected_version}-*.pkg.tar.*" | head -n 1)
  if [[ -z "$pkg_file" ]]; then
    echo -e "\e[31mFailed to download $pkg $selected_version to cache/\e[0m"
    return
  fi

  echo "Downgrading $pkg to $selected_version from cache/ ..."
  sudo pacman -U --needed "$pkg_file"

  # Prompt to add to ignore list
  read -p "Add $pkg to IgnorePkg? [y/N]: " add_ignore
  if [[ "$add_ignore" =~ ^[Yy]$ ]]; then
    sudo cp /etc/pacman.conf /etc/pacman.conf.bak
    if grep -q "^IgnorePkg" /etc/pacman.conf; then
      sudo sed -i "/^IgnorePkg/ s/$/ $pkg/" /etc/pacman.conf
    else
      sudo sed -i "/^#IgnorePkg/ c\IgnorePkg=$pkg" /etc/pacman.conf
    fi
    echo -e "\e[32m$pkg added to IgnorePkg.\e[0m"
  fi
}

# Downgrade multiple packages, one by one
downgrade_pacman_packages() {
  local packman_cached_packages=("$@")
  if [[ ${#packman_cached_packages[@]} -eq 0 ]]; then
    echo "No packages selected."
    return
  fi
  for pkg in "${packman_cached_packages[@]}"; do
    downgrade_single_pacman_package "$pkg"
    echo -e
    read -p "Press any key to continue..." -n 1
    clear
  done
}


ignore_packages() {
  clear

  echo -e "\e[32mSelect packages to ignore\e[0m"
  echo -e "\e[33mNote: Use SHIFT+TAB to select multiple packages\e[0m"

  if [[ -n "$pacman_cached_packages" ]]; then
    echo -e "\e[34mAdding packages to IgnorePkg...\e[0m"

    sudo cp /etc/pacman.conf /etc/pacman.conf.bak

    sudo sed -i "/^#IgnorePkg/ c\IgnorePkg=$pacman_cached_packages" /etc/pacman.conf

    echo -e "\e[32mPackages added to IgnorePkg successfully!\e[0m"
    read -p "Press any key to continue..." -n 1
  else
    echo -e "\e[31mNo packages selected.\e[0m"
    read -p "Press any key to continue..." -n 1
  fi
  clear
}