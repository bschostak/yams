#!/bin/bash

function install_paru_pkgs() {
    packages=("$@")

    if [[ -n "${packages[*]}" ]]; then
        echo "Installing selected pkgs: ${packages[*]}"
        echo -e
        # shellcheck disable=SC2046
        paru -S --needed "${packages[@]}" || echo "Some packages may not be available."
    else
        echo "No packages selected."
    fi
}

function update_paru_pkgs() {
    echo -e "\e[33mUpdating Paru packages...\e[0m"
    echo -e

	paru -Sua

    echo -e "\e[32mParu packages updated.\e[0m"
    echo -e
}