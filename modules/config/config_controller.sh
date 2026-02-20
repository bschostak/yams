#!/bin/bash

setup_config() {
    CONFIG_FILE="$HOME/.config/bptui/config.sh"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Configuration file not found. Creating default config..."
        
        mkdir -p "$HOME/.config/bptui"
        
        cat <<EOF > "$CONFIG_FILE"
#!/bin/bash

USE_PACMAN=true
USE_FLATPAK=false
USE_PARU=false
USE_YAY=false
USE_SNAP=false

DEBUG_MODE=false
EOF

        echo "Default configuration created at $CONFIG_FILE"
    fi
}
