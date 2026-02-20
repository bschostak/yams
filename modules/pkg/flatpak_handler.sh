#!/bin/bash

function install_flatpak_pkgs() {
  packages=("$@")

  if [[ -n "${packages[*]}" ]]; then
    echo "Installing selected pkgs: ${packages[*]}"
    # flatpak install flathub $(echo "${packages[@]}" | tr '\n' ' ') || echo "Some packages may not be available."
    flatpak install flathub "${packages[@]}" || echo "Some packages may not be available."
  else
    echo "No packages selected."
  fi
}

function remove_flatpak_pkgs() {
  packages=("$@")

  if [[ -n "${packages[*]}" ]]; then
    echo "Removing selected pkgs: '${packages[*]}'"
    # shellcheck disable=SC2046
    flatpak uninstall $(echo "${packages[@]}" | tr '\n' ' ') || echo "Some packages may not be available."
    echo -e
    echo "Removing unused dependencies..."
    flatpak uninstall --unused
  else
    echo "No packages selected."
  fi
}

function update_flatpak_pkgs() {
  echo -e "\e[33mUpdating Flatpak packages...\e[0m"
  echo -e

  sudo flatpak update

  echo -e "\e[32mFlatpak packages updated.\e[0m"
  echo -e
}
