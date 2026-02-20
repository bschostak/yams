#!/usr/bin/bash

source "modules/tui/tui_controller.sh"
source "$HOME/.config/bptui/config.sh"

declare -a PACKAGE_MANAGERS
declare -a OPTIONS
declare -a NEW_OPTIONS

get_pkg_mngrs_values() {
    if [[ "$USE_PACMAN" == true ]]; then
        PACKAGE_MANAGERS+=("is_pacman")
    fi
    if [[ "$USE_FLATPAK" == true ]]; then
        PACKAGE_MANAGERS+=("is_faltpak")
    fi
    if [[ "$USE_PARU" == true ]]; then
        PACKAGE_MANAGERS+=("is_paru")
    fi
    if [[ "$USE_YAY" == true ]]; then
        PACKAGE_MANAGERS+=("is_yay")
    fi
    if [[ "$USE_SNAP" == true ]]; then
        PACKAGE_MANAGERS+=("is_snap")
    fi
}

get_options_values() {
    if [[ "$DEBUG_MODE" == true ]]; then
        OPTIONS+=("is_debug_mode")
    fi
}

set_pkg_mngrs_values() {
    sed -i 's/USE_PACMAN=true/USE_PACMAN=false/' "$HOME/.config/bptui/config.sh"
    sed -i 's/USE_FLATPAK=true/USE_FLATPAK=false/' "$HOME/.config/bptui/config.sh"
    sed -i 's/USE_PARU=true/USE_PARU=false/' "$HOME/.config/bptui/config.sh"
    sed -i 's/USE_YAY=true/USE_YAY=false/' "$HOME/.config/bptui/config.sh"
    sed -i 's/USE_SNAP=true/USE_SNAP=false/' "$HOME/.config/bptui/config.sh"

    for value in "${NEW_OPTIONS[@]}"; do
        case "$value" in
            is_pacman) sed -i 's/USE_PACMAN=false/USE_PACMAN=true/' "$HOME/.config/bptui/config.sh" ;;
            is_faltpak) sed -i 's/USE_FLATPAK=false/USE_FLATPAK=true/' "$HOME/.config/bptui/config.sh" ;;
            is_paru) sed -i 's/USE_PARU=false/USE_PARU=true/' "$HOME/.config/bptui/config.sh" ;;
            is_yay) sed -i 's/USE_YAY=false/USE_YAY=true/' "$HOME/.config/bptui/config.sh" ;;
            is_snap) sed -i 's/USE_SNAP=false/USE_SNAP=true/' "$HOME/.config/bptui/config.sh" ;;
        esac
    done
}

set_options_values() {
    sed -i 's/PRINT_PKG_INFO=true/PRINT_PKG_INFO=false/' "$HOME/.config/bptui/config.sh"
    sed -i 's/DEBUG_MODE=true/DEBUG_MODE=false/' "$HOME/.config/bptui/config.sh"

    for value in "${NEW_OPTIONS[@]}"; do
        case "$value" in
            is_show_pkg_info) sed -i 's/PRINT_PKG_INFO=false/PRINT_PKG_INFO=true/' "$HOME/.config/bptui/config.sh" ;;
            is_debug_mode) sed -i 's/DEBUG_MODE=false/DEBUG_MODE=true/' "$HOME/.config/bptui/config.sh" ;;
        esac
    done
}

select_options() {
    clear

    get_pkg_mngrs_values
    get_options_values

    # ui_key_input -d
    echo -e "\e[4mbptui Options\e[24m"
    declare -A options2=([is_pacman]="Enable Pacman" [is_faltpak]="Enable Flatpak" [is_paru]="Enable Paru" [is_yay]="Enable YAY" [is_snap]="Enable Snap" [is_debug_mode]="Enable Debug Mode")
    ui_widget_select -l -m -s "${PACKAGE_MANAGERS[@]}" "${OPTIONS[@]}" -k "${!options2[@]}" -s bar -i "${options2[@]}"

    # echo "Return code: $?"
    # echo "Selected item(s): ${UI_WIDGET_RC[@]}"

    if [[ ${#UI_WIDGET_RC[@]} -eq 0 ]]; then
        return
    else
        for value in "${UI_WIDGET_RC[@]}"; do
            NEW_OPTIONS+=("$value")
        done
    fi

    set_pkg_mngrs_values
    set_options_values

    #NOTE: This is a temporary solution until I find a better way to handle this
    clear
    exit 0
}
