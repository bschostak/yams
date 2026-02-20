#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$HOME/.config/bptui/config.sh"

source "$script_dir/pacman_handler.sh"
source "$script_dir/flatpak_handler.sh"
source "$script_dir/paru_handler.sh"

function update_all_pkgs() {
    if [[ "$USE_PACMAN" == true ]]; then
    clear
    update_pacman_pkgs
    read -p "Press any key to continue..." -n 1
    fi

    if [[ "$USE_FLATPAK" == true ]]; then
    clear
    update_flatpak_pkgs
    read -p "Press any key to continue..." -n 1
    fi
    
    if [[ "$USE_PARU" == true ]]; then
    clear
    update_paru_pkgs
    read -p "Press any key to continue..." -n 1
    fi
    
    if [[ "$USE_YAY" == true ]]; then
    #TODO: Implement yay update function
    echo "YAY update function not implemented yet."
    fi

    if [[ "$USE_SNAP" == true ]]; then
    #TODO: Implement snap update function
    echo "Snap update function not implemented yet."
    fi
}

function update_specific_pkgs() {
    options[0]="Pacman"
    options[1]="Flatpak"
    options[2]="Paru"
    options[3]="YAY"
    options[4]="Snap"
    #TODO: Implement the rest of the options
}