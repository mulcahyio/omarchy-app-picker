# Omarchy App Picker — Development Notes

| | |
|---|---|
| **Version** | 1.0.0 |
| **Plugin id** | `mulcahyio.app-picker` |
| **Built on** | Omarchy 4.0.4 shell plugin system (Quickshell 0.3.1, Qt 6, Hyprland 0.56.2) |

## How it fits into Omarchy

The Omarchy bar, menus and overlays all run in one long-lived Quickshell
process, `omarchy-shell`. It loads first-party plugins from
`/usr/share/omarchy/shell/plugins/` and user plugins from
`~/.config/omarchy/plugins/<id>/`. A plugin is a folder with a
`manifest.json` and QML entry points.

The App Picker is one plugin with two kinds:

| Kind | Entry point | What the shell does with it |
|---|---|---|
| `menu` | `AppPicker.qml` | Loads it and calls `open(payloadJson)` / `close()` when it is summoned or hidden |
| `bar-widget` | `BarWidget.qml` | Places the icon in the bar where `shell.json` says |

`keepLoaded: true` keeps the picker in memory between opens, so it opens
instantly and its app list and icon index are already built.

Opening and closing go through the shell's IPC:

```bash
omarchy-shell shell toggle mulcahyio.app-picker   # keybinding and bar icon
omarchy-shell shell summon mulcahyio.app-picker '{}'
omarchy-shell shell hide   mulcahyio.app-picker
```

Inside the picker, Esc, launching an app and ✕ call `dismiss()`, which asks
the shell to hide the plugin, so the shell's open/closed state stays in step.

## App list

The picker shows exactly what the Omarchy Apps menu shows. It uses Omarchy's
own `AppLibrary` component (`/usr/share/omarchy/shell/services/AppLibrary.qml`,
imported as `qs.services`), which provides:

- the desktop entries (Quickshell `DesktopEntries`), minus entries hidden by
  `NoDisplay`, `OnlyShowIn`/`NotShowIn` and Omarchy's `launcher.hides` list;
- the same search ranking as the Apps menu (`sortedEntries(query)`);
- icon lookup with Omarchy's fallback icon index;
- launching through `uwsm-app -- gtk-launch <id>.desktop`, with Omarchy's
  "Launching…" feedback.

The shell is meant to pass menu plugins an app-library facade
(`shell.appLibrary`). On Omarchy 4.0.4 that facade arrives as `null` for
third-party plugins, so the picker creates its own `AppLibrary` instance and
uses the facade only when one is provided. Either way the behaviour matches the
Apps menu.

The picker keeps its own list (`allApps`) of `{id, name, icon, subtext}` and
derives what the grid shows (`apps`) from it: favorites view or all apps,
sorted by name with `localeCompare` (A → Z or Z → A), filtered by the search.
The grid model is only replaced when the list of visible ids changes, so
changing a favorite doesn't reset the grid or its scroll position.

## Layout

- `PanelWindow` on the `Overlay` layer, anchored to all four edges, with
  exclusive keyboard focus and `ExclusionMode.Ignore` (covers the bar).
  No screen is set, so Hyprland opens it on the focused monitor.
- Full screen: the card fills the window. Window mode: the card is 72 % × 78 %
  of the screen (minimum 560 × 420 logical px) over a dimmed background.
- Grid: target tile size is `min(card width, card height × 16/9) / 11`,
  clamped to 110–180 logical px (scaled with Omarchy's spacing scale).
  `columns = floor(width / target)` and `cell = floor(width / columns)`, so
  columns divide the width evenly and the grid is centered.
- Colours come from the theme's `[menu]` colours (`Color.menu.*`), fonts and
  spacing from `Style`, so the picker follows the Omarchy theme.

## Favorites and drag and drop

Favorites are an ordered list of desktop ids; rank = position + 1.

Drag and drop is done by hand rather than with Qt's `Drag`/`DropArea`, so a
drag can start from a grid tile or a favorite chip and drop anywhere:

1. `pressOn()` records the app and press point (in `dragLayer` coordinates).
2. `moveOn()` starts the drag after 8 px, moves the floating copy and works
   out `dropIndex`, the insertion slot in the Favorites box, from the chip
   positions in reading order (`favoritesDropIndex()`).
3. `releaseOn()` applies the drop after the release handler returns
   (`Qt.callLater`), because the change rebuilds the chips: dropping in the
   box places the app at `dropIndex`; dropping a favorite outside the box
   removes it.

Tile and chip `MouseArea`s use `preventStealing` so the grid doesn't flick
during a drag. Hover changes the selection only when the pointer actually
moves, so a redraw under a resting pointer doesn't steal the keyboard
selection.

## Saved state

`~/.local/state/omarchy-app-picker.json`:

```json
{
  "version": 1,
  "sortOrder": "asc",
  "view": "all",
  "fullscreen": true,
  "favorites": ["org.gnome.Nautilus", "chromium"]
}
```

It lives outside the plugin folder on purpose: the shell reloads a plugin
whenever a file in its folder changes.

## Developing

- Edit the files in `~/.config/omarchy/plugins/mulcahyio.app-picker/` (a git
  checkout after `install.sh`), then run `omarchy restart shell`. The shell
  logs "Local plugin changed" on save, but a kept-loaded plugin keeps running
  the old code until the shell restarts.
- Validate the manifest: `omarchy plugin validate .`
- Lint the QML: `/usr/lib/qt6/bin/qmllint AppPicker.qml BarWidget.qml`
- Shell log: `quickshell log --pid $(pgrep -f "quickshell -n -p /usr/share/omarchy/shell")`
- When testing with simulated keys (`wtype`), check that the picker is open
  first (screenshot with `grim`), otherwise the keys go to whatever window
  has focus.

## Testing done for 1.0.0

On Omarchy 4.0.4, one 1920 × 1080 monitor:

| Area | Result |
|---|---|
| Manifest validation, QML lint | Pass |
| Opens from the shell command and bar icon; full screen covers the bar | Pass |
| All 43 apps from the Apps menu, with icons and names | Pass |
| A → Z, Z → A, search | Pass |
| Window mode and back | Pass |
| Ctrl+F add/remove favorite, Favorites view, rank badges | Pass |
| Ctrl+← / Ctrl+→ rank changes, selection follows the moved app | Pass |
| Settings saved and restored | Pass |
| `install.sh`: fresh install, bar placement after the Omarchy icon, Super + A binding, shell restart | Pass |
| `install.sh` re-run: replaces the copy, still one keybinding block | Pass |
| `install.sh --key` on a taken key: warns and leaves the existing binding | Pass |
| `install.sh` without a terminal and without `--yes`: refuses to replace | Pass |
| `uninstall.sh`: disables, removes bar icon, keybinding block and folder | Pass |
| Installed copy is on `main` tracking GitHub; `git pull` and `omarchy plugin update` work | Pass |
| ShellCheck (warnings) on both scripts | Pass |
| `bindings.conf` (older Hyprland config) path | Not tested |
| Mouse drag-and-drop | Not tested (no way to simulate mouse drags) |
| Multiple monitors, HiDPI scaling | Not tested |

## Releasing

1. Update `version` in `manifest.json` and add a section to `CHANGELOG.md`.
2. Commit, tag `vX.Y.Z`, push the branch and the tag.
3. Create a GitHub release from the tag with the CHANGELOG section as notes.
