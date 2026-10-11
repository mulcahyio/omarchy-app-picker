#!/usr/bin/env bash
# Omarchy App Picker uninstaller.
#
# Disables the plugin, removes its bar icon and the keybinding block that
# install.sh added, deletes the plugin folder and restarts the Omarchy shell.
# Your favorites and settings are kept unless you pass --purge.
#
# Usage: ./uninstall.sh [--purge] [--no-restart] [--yes] [--help]
set -euo pipefail

PLUGIN_ID="mulcahyio.app-picker"
TARGET="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
STATE_FILE="$HOME/.local/state/omarchy-app-picker.json"
MARK_BEGIN="-- >>> omarchy-app-picker (managed by install.sh, removed by uninstall.sh)"
MARK_END="-- <<< omarchy-app-picker"
CONF_MARK_BEGIN="# >>> omarchy-app-picker (managed by install.sh, removed by uninstall.sh)"
CONF_MARK_END="# <<< omarchy-app-picker"

PURGE=0
RESTART=1
ASSUME_YES=0

ok()   { printf '  \033[32m[ OK ]\033[0m %s\n' "$*"; }
info() { printf '  \033[34m[INFO]\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

while (( $# )); do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --no-restart) RESTART=0; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --help|-h) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown option: $1 (see --help)" ;;
  esac
done

if (( ! ASSUME_YES )); then
  [[ -t 0 ]] || fail "Re-run with --yes to uninstall without a prompt."
  read -rp "  Remove the App Picker$( (( PURGE )) && echo ' and its favorites/settings')? [y/N] " reply
  [[ $reply == [yY]* ]] || fail "Cancelled; nothing changed."
fi

echo
echo "  Omarchy App Picker - uninstall"
echo

# Close it if it is open, then disable (removes the bar entry from shell.json).
omarchy-shell -q shell hide "$PLUGIN_ID" || true
if command -v omarchy-plugin-disable >/dev/null && omarchy plugin list 2>/dev/null | grep -qE "^$PLUGIN_ID +enabled"; then
  omarchy-plugin-disable "$PLUGIN_ID" >/dev/null
  ok "Disabled $PLUGIN_ID and removed its bar icon"
else
  info "Plugin was not enabled"
fi

# Remove the keybinding block.
remove_block() {  # file begin end
  [[ -f $1 ]] && grep -qxF "$2" "$1" || return 1
  cp -- "$1" "$1.bak.app-picker.$(date +%Y%m%d-%H%M%S)"
  awk -v b="$2" -v e="$3" '$0==b{skip=1; next} $0==e{skip=0; next} !skip' "$1" > "$1.tmp.$$" && mv -- "$1.tmp.$$" "$1"
}
removed_key=0
remove_block "$HOME/.config/hypr/bindings.lua" "$MARK_BEGIN" "$MARK_END" && removed_key=1
remove_block "$HOME/.config/hypr/bindings.conf" "$CONF_MARK_BEGIN" "$CONF_MARK_END" && removed_key=1
if (( removed_key )); then
  command -v hyprctl >/dev/null && hyprctl reload >/dev/null || true
  ok "Removed the keybinding"
else
  info "No keybinding block found"
fi

# Remove the files. This is safe even when the script runs from that folder:
# bash keeps reading it through its open file handle.
if [[ -d $TARGET ]]; then
  rm -rf -- "$TARGET"
  ok "Removed $TARGET"
else
  info "$TARGET was already gone"
fi

if (( PURGE )); then
  rm -f -- "$STATE_FILE"
  ok "Removed favorites and settings ($STATE_FILE)"
elif [[ -f $STATE_FILE ]]; then
  info "Kept favorites and settings in $STATE_FILE (use --purge to remove)"
fi

if (( RESTART )); then
  omarchy restart shell >/dev/null 2>&1 || true
  ok "Restarted the Omarchy shell"
fi

echo
echo "  App Picker removed."
echo
