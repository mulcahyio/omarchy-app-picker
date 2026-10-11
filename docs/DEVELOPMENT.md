# Omarchy App Picker — Development Guide

| | |
|---|---|
| **Version** | 1.0.2 |
| **Plugin id** | `mulcahyio.app-picker` |
| **Developed by** | Patrick Mulcahy · dev@mulcahy.io |
| **License** | MIT (see `LICENSE`) |

How the plugin is built — components, Omarchy integration, data model, flows
and design decisions — is in [ARCHITECTURE.md](ARCHITECTURE.md). This guide
covers working on it: editing, checking, testing and releasing.

## Working copy

After `install.sh`, the installed plugin at
`~/.config/omarchy/plugins/mulcahyio.app-picker/` is a git checkout of this
repository on `main`. You can edit there directly, or edit a separate clone
and re-run its `install.sh --yes`.

After any change to `AppPicker.qml`, `BarWidget.qml` or `manifest.json`:

```bash
omarchy restart shell
```

The shell logs "Local plugin changed" when a file is saved, but because the
plugin is `keepLoaded`, the running copy keeps the old code until the shell
restarts.

## Checks

| Check | Command |
|---|---|
| Manifest | `omarchy plugin validate .` |
| QML lint | `/usr/lib/qt6/bin/qmllint AppPicker.qml BarWidget.qml` |
| Shell scripts | `docker run --rm -v "$PWD":/mnt:ro koalaman/shellcheck:v0.10.0 -S warning /mnt/install.sh /mnt/uninstall.sh` |
| Shell log | `quickshell log --pid $(pgrep -f "quickshell -n -p /usr/share/omarchy/shell")` |

## Testing

Open, close and screenshot from a terminal:

```bash
omarchy-shell shell summon mulcahyio.app-picker '{}'
grim /tmp/picker.png
omarchy-shell shell hide mulcahyio.app-picker
```

Keyboard tests can be driven with `wtype`. **Confirm the picker is open
first** (take a screenshot): if it isn't, the keys go to whatever window has
focus. Close it with `omarchy-shell shell hide …` rather than a simulated
Esc.

Test favorites against a throwaway state file, then delete it:
`rm ~/.local/state/omarchy-app-picker.json && omarchy restart shell`.

### Test record

On Omarchy 4.0.4, Hyprland 0.56.2, one 1920 × 1080 monitor:

| Area | 1.0.0 | 1.0.1 | 1.0.2 |
|---|---|---|---|
| Manifest validation, QML lint | Pass | Pass | Pass |
| Opens from the shell command and bar icon; full screen covers the bar | Pass | Pass | Pass |
| All 43 apps from the Apps menu, with icons and names | Pass | Pass | Pass |
| A → Z, Z → A, search | Pass | — (no code change) | — |
| Window mode and back | Pass | — | — |
| Ctrl+F add/remove favorite, Favorites view, rank badges | Pass | — | — |
| Ctrl+← / Ctrl+→ rank changes, selection follows the moved app | Pass | — | — |
| Settings saved and restored across shell restarts | Pass | — | Pass (favorites kept across uninstall and reinstall) |
| `install.sh` fresh install: bar icon after the Omarchy icon, Super + A, shell restart | Pass | Pass | Pass |
| `install.sh` re-run: replaces the copy, still one keybinding block, no extra blank lines | Pass | Pass | — |
| `install.sh --key` on a taken key: warns, leaves the existing binding | Pass | Pass | — |
| `install.sh` without a terminal and without `--yes`: refuses to replace | Pass | Pass | — |
| `install.sh` from a release-tag (detached) checkout: installed on `main`, tracking GitHub | — | Pass | — |
| `install.sh` from a zip (no `.git`): files copied | — | Pass | — |
| `omarchy plugin add … --enable --yes`, then `install.sh` from the plugin folder for the keybinding | — | Pass | — |
| `git pull` and `omarchy plugin update` on the installed copy | Pass | Pass | — |
| `uninstall.sh`: disables, removes bar icon, keybinding block and folder | Pass | Pass | Pass |
| ShellCheck (warnings) on both scripts | Pass | Pass | Pass |
| `bindings.conf` (older Hyprland config) | Not tested | Not tested | Not tested |
| Mouse: drag an app into Favorites, reorder by dragging, remove by dragging out / ✕ | Not tested | Pass (by hand, Patrick Mulcahy, 2026-10-11) | — |
| All other functions, by hand | — | Pass (Patrick Mulcahy, 2026-10-11; no issues found) | — |
| Multiple monitors, HiDPI scaling | Not tested | Not tested | Not tested |

## Releasing

1. Update `version` in `manifest.json`, the version in the headers of
   `README.md` and the documents in `docs/`, and add a section to
   `CHANGELOG.md`.
2. Run the checks above and update the test record.
3. Commit, tag `vX.Y.Z` (annotated), push `main` and the tag.
4. Create a GitHub release from the tag with the CHANGELOG section as notes.
5. Update the installed copy: `omarchy plugin update mulcahyio.app-picker`
   and `omarchy restart shell`.
