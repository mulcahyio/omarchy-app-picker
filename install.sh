#!/usr/bin/env bash
# Omarchy App Picker installer.
#
# Installs the plugin as a git checkout in ~/.config/omarchy/plugins/
# (the same layout `omarchy plugin add` uses, so `omarchy plugin update`
# works later), enables it in the bar next to the Omarchy icon, adds a
# keybinding, and restarts the Omarchy shell so the plugin loads.
#
# Usage: ./install.sh [--key "SUPER + A"] [--no-keybinding] [--force-key]
#                     [--no-restart] [--yes] [--help]
set -euo pipefail

PLUGIN_ID="mulcahyio.app-picker"
REPO_URL_DEFAULT="https://github.com/mulcahyio/omarchy-app-picker.git"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
TARGET="$PLUGINS_DIR/$PLUGIN_ID"
TOGGLE_CMD="omarchy-shell shell toggle $PLUGIN_ID"
MARK_BEGIN="-- >>> omarchy-app-picker (managed by install.sh, removed by uninstall.sh)"
MARK_END="-- <<< omarchy-app-picker"
CONF_MARK_BEGIN="# >>> omarchy-app-picker (managed by install.sh, removed by uninstall.sh)"
CONF_MARK_END="# <<< omarchy-app-picker"

KEY="SUPER + A"
ADD_KEY=1
FORCE_KEY=0
RESTART=1
ASSUME_YES=0

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

ok()   { printf '  \033[32m[ OK ]\033[0m %s\n' "$*"; }
info() { printf '  \033[34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m[WARN]\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'
Options:
  --key "MODS + KEY"   Keybinding to open the picker (default "SUPER + A").
  --no-keybinding      Don't add a keybinding (use the bar icon instead).
  --force-key          Use --key even if Hyprland already binds it; the
                       existing binding is unbound first.
  --no-restart         Don't restart the Omarchy shell (the plugin loads on
                       the next restart or login).
  --yes                Don't ask before replacing an existing install.
EOF
}

while (( $# )); do
  case "$1" in
    --key) KEY="${2:-}"; [[ -n $KEY ]] || fail "--key needs a value, e.g. --key \"SUPER + A\""; shift 2 ;;
    --no-keybinding) ADD_KEY=0; shift ;;
    --force-key) FORCE_KEY=1; shift ;;
    --no-restart) RESTART=0; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "unknown option: $1 (see --help)" ;;
  esac
done

confirm() {
  (( ASSUME_YES )) && return 0
  [[ -t 0 ]] || fail "$1 Re-run with --yes to confirm without a prompt."
  local reply
  read -rp "  $1 [y/N] " reply
  [[ $reply == [yY]* ]]
}

echo
echo "  Omarchy App Picker - install"
echo

# --- Requirements ----------------------------------------------------------
for cmd in omarchy omarchy-shell omarchy-plugin-enable omarchy-plugin-validate git jq hyprctl; do
  command -v "$cmd" >/dev/null || fail "'$cmd' not found. This installer needs Omarchy 4 or later with Hyprland."
done
omarchy-shell shell ping >/dev/null 2>&1 || fail "The Omarchy shell is not running. Log in to your Omarchy desktop and run this again."
version=$(omarchy version 2>/dev/null || echo unknown)
major=${version%%.*}
if [[ $major =~ ^[0-9]+$ ]] && (( major < 4 )); then
  fail "Omarchy $version is too old; the shell plugin system needs Omarchy 4 or later."
fi
ok "Omarchy $version with the shell running"

[[ -f $SCRIPT_DIR/manifest.json ]] || fail "manifest.json not found next to install.sh. Run this from the repository folder."
omarchy-plugin-validate "$SCRIPT_DIR" >/dev/null || fail "The plugin manifest did not validate."
plugin_version=$(jq -r '.version' "$SCRIPT_DIR/manifest.json")
ok "Plugin $PLUGIN_ID $plugin_version is valid"

# --- Plugin files ------------------------------------------------------------
# Clone this checkout into the plugins folder, then point its origin at the
# public repository so `omarchy plugin update` pulls from GitHub.
origin_url=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "$REPO_URL_DEFAULT")
mkdir -p "$PLUGINS_DIR"
if [[ $SCRIPT_DIR == "$TARGET" ]]; then
  ok "Running from the installed plugin folder; files are already in place"
else
  if [[ -e $TARGET ]]; then
    confirm "$TARGET already exists. Replace it?" || fail "Cancelled; nothing changed."
    rm -rf -- "$TARGET"
  fi
  stage="$PLUGINS_DIR/.app-picker.tmp.$$"
  trap 'rm -rf -- "$stage"' EXIT
  if git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    # Install the exact commit being run, on a named branch that tracks the
    # same branch on GitHub, so both `git pull` and `omarchy plugin update`
    # can fast-forward the install later. A checkout of a release tag is
    # detached; it is installed on `main`.
    branch=$(git -C "$SCRIPT_DIR" symbolic-ref --short -q HEAD || echo main)
    git clone --quiet --no-checkout -- "$SCRIPT_DIR" "$stage"
    git -C "$stage" checkout --quiet -B "$branch" "$(git -C "$SCRIPT_DIR" rev-parse HEAD)"
    git -C "$stage" remote set-url origin "$origin_url"
    git -C "$stage" config "branch.$branch.remote" origin
    git -C "$stage" config "branch.$branch.merge" "refs/heads/$branch"
  else
    # Unpacked from a zip/tarball: copy the files as they are.
    mkdir -p "$stage"
    cp -a "$SCRIPT_DIR"/. "$stage"/
  fi
  mv -- "$stage" "$TARGET"
  trap - EXIT
  ok "Installed files to $TARGET"
fi

# --- Enable and place in the bar ---------------------------------------------
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
placement=(--section left)
if jq -e '[.. | objects | select(.id? == "omarchy.menu")] | length > 0' "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1; then
  placement+=(--after omarchy.menu)
fi
if omarchy plugin list 2>/dev/null | grep -qE "^$PLUGIN_ID +enabled"; then
  ok "Plugin already enabled"
else
  omarchy-plugin-enable "$PLUGIN_ID" "${placement[@]}" >/dev/null
  ok "Enabled $PLUGIN_ID (bar icon: ${placement[*]})"
fi

# --- Keybinding --------------------------------------------------------------
# "SUPER + SHIFT + A" -> modmask and key, as hyprctl reports them.
key_modmask() {
  local mask=0 part
  IFS='+' read -ra parts <<< "$1"
  for part in "${parts[@]:0:${#parts[@]}-1}"; do
    case "$(echo "$part" | tr -d ' ' | tr '[:lower:]' '[:upper:]')" in
      SHIFT) mask=$((mask | 1)) ;;
      CAPS) mask=$((mask | 2)) ;;
      CTRL|CONTROL) mask=$((mask | 4)) ;;
      ALT) mask=$((mask | 8)) ;;
      MOD2) mask=$((mask | 16)) ;;
      MOD3) mask=$((mask | 32)) ;;
      SUPER|WIN|LOGO|MOD4) mask=$((mask | 64)) ;;
      MOD5) mask=$((mask | 128)) ;;
      *) fail "unknown modifier '$part' in --key \"$1\"" ;;
    esac
  done
  echo "$mask"
}
key_name() { local k="${1##*+}"; echo "$k" | tr -d ' '; }

remove_block() {  # file begin end
  [[ -f $1 ]] || return 0
  awk -v b="$2" -v e="$3" '$0==b{skip=1; next} $0==e{skip=0; next} !skip' "$1" > "$1.tmp.$$" && mv -- "$1.tmp.$$" "$1"
}

if (( ADD_KEY )); then
  lua="$HOME/.config/hypr/bindings.lua"
  conf="$HOME/.config/hypr/bindings.conf"
  mask=$(key_modmask "$KEY")
  key=$(key_name "$KEY")
  [[ -n $key ]] || fail "no key in --key \"$KEY\""

  # Who holds this key now (ignoring our own previous binding)?
  holder=$(hyprctl binds -j | jq -r --argjson m "$mask" --arg k "$key" --arg cmd "$TOGGLE_CMD" '
    [.[] | select(.modmask == $m and (.key | ascii_upcase) == ($k | ascii_upcase))
         | select((.arg // "" | tostring) | contains($cmd) | not)
         | select((.description // "") != "App Picker")
         | (.description // .arg // "another action")][0] // empty')
  unbind=0
  if [[ -n $holder ]]; then
    if (( FORCE_KEY )); then
      warn "\"$KEY\" was bound to \"$holder\"; it will be unbound and used for the App Picker"
      unbind=1
    else
      warn "\"$KEY\" is already bound to \"$holder\". Skipping the keybinding."
      warn "Pick a free key with --key \"MODS + KEY\" (see: omarchy menu keybindings --print), or take this one with --force-key."
      ADD_KEY=0
    fi
  fi

  if (( ADD_KEY )); then
    stamp=$(date +%Y%m%d-%H%M%S)
    if [[ -f $lua ]]; then
      cp -- "$lua" "$lua.bak.app-picker.$stamp"
      remove_block "$lua" "$MARK_BEGIN" "$MARK_END"
      {
        [[ -n $(tail -n1 "$lua") ]] && echo
        echo "$MARK_BEGIN"
        (( unbind )) && echo "hl.unbind(\"$KEY\")"
        echo "o.bind(\"$KEY\", \"App Picker\", \"$TOGGLE_CMD\")"
        echo "$MARK_END"
      } >> "$lua"
      bindfile=$lua
    elif [[ -f $conf ]]; then
      cp -- "$conf" "$conf.bak.app-picker.$stamp"
      remove_block "$conf" "$CONF_MARK_BEGIN" "$CONF_MARK_END"
      mods=$(echo "${KEY%+*}" | tr '+' ' ' | tr -s ' ' | sed 's/^ //;s/ $//')
      {
        [[ -n $(tail -n1 "$conf") ]] && echo
        echo "$CONF_MARK_BEGIN"
        (( unbind )) && echo "unbind = $mods, $key"
        echo "bindd = $mods, $key, App Picker, exec, $TOGGLE_CMD"
        echo "$CONF_MARK_END"
      } >> "$conf"
      bindfile=$conf
    else
      fail "No ~/.config/hypr/bindings.lua or bindings.conf found. Re-run with --no-keybinding."
    fi
    hyprctl reload >/dev/null
    sleep 0.5
    errors=$(hyprctl configerrors 2>/dev/null | grep -v '^\s*$' || true)
    if [[ -n $errors ]]; then
      warn "Hyprland reports config errors after the change:"
      echo "$errors" | sed 's/^/        /'
      warn "A backup of the previous file is next to it (*.bak.app-picker.$stamp)."
    fi
    if hyprctl binds -j | jq -e --argjson m "$mask" --arg k "$key" \
         'any(.[]; .modmask == $m and (.key | ascii_upcase) == ($k | ascii_upcase) and ((.description // "") == "App Picker" or ((.arg // "" | tostring) | contains("app-picker"))))' >/dev/null; then
      ok "Keybinding $KEY added in $bindfile"
    else
      warn "Keybinding written to $bindfile, but Hyprland doesn't report it yet. Check with: hyprctl binds"
    fi
  fi
else
  info "Skipped the keybinding (--no-keybinding)"
fi

# --- Load it -----------------------------------------------------------------
if (( RESTART )); then
  omarchy restart shell >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do omarchy-shell shell ping >/dev/null 2>&1 && break; sleep 0.25; done
  ok "Restarted the Omarchy shell"
else
  info "Restart the shell to load the plugin: omarchy restart shell"
fi

echo
echo "  App Picker $plugin_version is installed."
(( ADD_KEY )) && echo "  Open it with $KEY or the grid icon next to the Omarchy icon in the bar."
(( ADD_KEY )) || echo "  Open it with the grid icon next to the Omarchy icon in the bar."
echo "  Remove it with: $TARGET/uninstall.sh"
echo
