#!/bin/bash

PIPE="/tmp/yad_info_$(date +%s)"
mkfifo "$PIPE"
exec 3<> "$PIPE"

# --- Function to Fetch Info ---
get_info() {
    while read -r line; do
        PKG=$(echo "$line" | cut -d'|' -f3)
        SRC=$(echo "$line" | cut -d'|' -f5)
        echo -e "\f" # Clear screen
        echo "DETAILS FOR: $PKG"
        echo "SOURCE: $SRC"
        echo "--------------------------"
        [[ "$SRC" == "Repo" ]] && pacman -Qi "$PKG" 2>/dev/null
        [[ "$SRC" == "Flatpak" ]] && flatpak info "$PKG" 2>/dev/null
        [[ "$SRC" == "AUR" ]] && echo "AUR querying logic here..."
    done
}

# --- THE PLUGS ---
KEY=$RANDOM

# 1. Action Bar (Search + Buttons)
yad --plug=$KEY --tabnum=1 --form --columns=5 \
    --field="Search:CE" "" \
    --field="Search:FBTN" 'bash -c "echo SEARCH"' \
    --field="Install!gtk-add:FBTN" 'bash -c "echo INSTALL"' \
    --field="Remove!gtk-remove:FBTN" 'bash -c "echo REMOVE"' \
    --field="Downgrade!gtk-undo:FBTN" 'bash -c "echo DOWNGRADE"' &

# 2. Package List
export PIPE
yad --plug=$KEY --tabnum=2 --list --checklist --multiple \
    --column="Select:CHK" --column="Status:IMG" --column="Package" --column="Version" --column="Source" --column="Description" \
    FALSE "gtk-apply" "linux-zen" "6.1.1" "Repo" "The Zen Kernel" \
    FALSE "gtk-refresh" "firefox" "126.0" "Flatpak" "Web Browser" \
    FALSE "gtk-close" "yay" "12.3" "AUR" "AUR Helper" \
    --select-action="bash -c 'echo \"%s\" > $PIPE'" &

# 3. Info Pane (The one you drew in red)
get_info < "$PIPE" | yad --plug=$KEY --tabnum=3 --text-info --listen --fontname="Monospace 10" &

# --- THE NESTING (This creates the split) ---
# First, we create a paned window that holds Plug 2 (list) and Plug 3 (info) vertically.
# Then we dock that inside the main container.
# However, YAD handles this more simply by just assigning tabnums to a vertical pane.

yad --paned --key=$KEY --title="Bash Package Manager" \
    --width=1000 --height=850 --orient=vertical \
    --menu="File|Quit!quit" \
    --button="Check for Updates!gtk-refresh:0" \
    --button="Exit!gtk-quit:1"

# Cleanup
exec 3>&-
rm "$PIPE"
killall yad 2>/dev/null