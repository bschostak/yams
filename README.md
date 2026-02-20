# yams
YAD Application Management Software.

## Requirements
- `yad` (GTK dialog tool)
- Package tools you enable in `~/.config/bptui/config.sh`:
  - `pacman` (and optionally `paru`)
  - `flatpak`

## Run
- From the repo: `./bptui.sh`
- After install: `bptui`

## GUI
The app uses a YAD GUI (action bar + package list + details pane) based on `test (yams).sh`.

Actions (`Install`, `Remove`, `Update`, `Downgrade`) open in a terminal window so you can enter your password for `sudo` and see full command output.
