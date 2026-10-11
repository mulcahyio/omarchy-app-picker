# Omarchy App Picker — Install Guide

| | |
|---|---|
| **Applies to** | Omarchy App Picker 1.0.1 |
| **Developed by** | Patrick Mulcahy · dev@mulcahy.io |
| **License** | MIT |

This guide covers installing, checking, updating and removing the App Picker
on an Omarchy system. For what the picker does, see the
[README](../README.md); for how it is built, see
[ARCHITECTURE.md](ARCHITECTURE.md).

## 1. Requirements

| Requirement | How to check |
|---|---|
| Omarchy 4.0 or later | `omarchy version` |
| You are logged in to the Omarchy desktop (the shell must be running) | `omarchy-shell shell ping` prints `ok` |
| `git` and `jq` (included with Omarchy) | `git --version`, `jq --version` |
| Access to the repository on GitHub (it is private) | `gh auth status`, or an SSH key on a GitHub account with access |

Tested on Omarchy 4.0.4 with Hyprland 0.56.2 and Quickshell 0.3.1.

Nothing needs `sudo`. Everything is installed in your home directory.

### Access to the repository

The repository is private. On a new machine, sign in to GitHub first with an
account that has access, using either:

```bash
gh auth login            # choose GitHub.com, HTTPS, and log in with a browser
```

or an SSH key added to that GitHub account, and clone with
`git@github.com:mulcahyio/omarchy-app-picker.git` instead of the HTTPS
URL below.

## 2. Install (recommended)

```bash
git clone https://github.com/mulcahyio/omarchy-app-picker.git
cd omarchy-app-picker
./install.sh
```

Expected output:

```
  Omarchy App Picker - install

  [ OK ] Omarchy 4.0.4-1 with the shell running
  [ OK ] Plugin mulcahyio.app-picker 1.0.1 is valid
  [ OK ] Installed files to /home/<you>/.config/omarchy/plugins/mulcahyio.app-picker
  [ OK ] Enabled mulcahyio.app-picker (bar icon: --section left --after omarchy.menu)
  [ OK ] Keybinding SUPER + A added in /home/<you>/.config/hypr/bindings.lua
  [ OK ] Restarted the Omarchy shell

  App Picker 1.0.1 is installed.
```

The top bar disappears for a second while the shell restarts. After that you
can delete the cloned folder; the installed copy is separate.

### Installer options

| Option | Use it when |
|---|---|
| `--key "SUPER + ALT + Y"` | You want a different shortcut. Check which keys are free with `omarchy menu keybindings --print`. |
| `--force-key` | You want the key even though something else uses it. The other binding is unbound. |
| `--no-keybinding` | You only want the bar icon. |
| `--no-restart` | You don't want the shell restarted now. The picker loads at the next restart or login. |
| `--yes` | You're scripting the install, or re-installing without being asked. |

Example: `./install.sh --key "SUPER + ALT + Y"`

### What the installer changes

| Location | Change | Backup |
|---|---|---|
| `~/.config/omarchy/plugins/mulcahyio.app-picker/` | Created (git checkout of the version you ran) | Replaced only after you confirm |
| `~/.config/omarchy/shell.json` | Bar entry for the plugin, after the Omarchy icon (via `omarchy plugin enable`) | — |
| `~/.config/hypr/bindings.lua` (or `bindings.conf`) | A marked block with the keybinding, at the end | `bindings.lua.bak.app-picker.<date-time>` |
| `~/.local/state/omarchy-app-picker.json` | Created the first time you change a setting or favorite | — |

Omarchy's own files in `/usr/share/omarchy` are not touched.

## 3. Other ways to install

### 3.1 A specific version

```bash
git clone --branch v1.0.1 https://github.com/mulcahyio/omarchy-app-picker.git
cd omarchy-app-picker
./install.sh
```

The installed copy is put on the `main` branch at that version, so a later
update moves it to the newest release.

### 3.2 With Omarchy's plugin command (no keybinding)

```bash
omarchy plugin add https://github.com/mulcahyio/omarchy-app-picker.git --enable --yes
omarchy restart shell
```

This installs and enables the plugin. With `--yes` the bar icon goes at the
end of the left section (after the workspace numbers); without it, you're
asked which section to use. It does **not** add a keybinding. To add
one later, run `install.sh` from the installed folder:

```bash
~/.config/omarchy/plugins/mulcahyio.app-picker/install.sh
```

### 3.3 From a downloaded zip (no git)

Download the source zip from the release page, unpack it, and run
`./install.sh` inside the unpacked folder. The files are copied as they are.
A zip install can't be updated with `git pull` or `omarchy plugin update`;
to update, download the new zip and run its `install.sh --yes`.

## 4. Check the install

| Check | Command | Expected |
|---|---|---|
| Plugin enabled | `omarchy plugin list \| grep app-picker` | `mulcahyio.app-picker  enabled  third-party  menu,bar-widget  App Picker` |
| Keybinding live | `hyprctl binds \| grep -B5 "description: App Picker"` | `modmask: 64` (Super) and `key: A`, or the key you chose |
| No config errors | `hyprctl configerrors` | Empty output |
| Opens | `omarchy-shell shell toggle mulcahyio.app-picker` | The picker opens; run it again to close |
| Version | `jq -r .version ~/.config/omarchy/plugins/mulcahyio.app-picker/manifest.json` | `1.0.1` |

Then try it: press **Super + A** (or click the grid icon next to the Omarchy
icon), type a few letters, press Enter.

## 5. Update

```bash
omarchy plugin update mulcahyio.app-picker
omarchy restart shell
```

or

```bash
cd ~/.config/omarchy/plugins/mulcahyio.app-picker
git pull
omarchy restart shell
```

The shell restart is needed: the shell keeps the loaded plugin in memory
until it restarts. Your favorites and settings are kept.

To change the keybinding after installing, run the installer again with the
new key; it replaces its own block:

```bash
~/.config/omarchy/plugins/mulcahyio.app-picker/install.sh --key "SUPER + ALT + Y" --yes
```

## 6. Uninstall

```bash
~/.config/omarchy/plugins/mulcahyio.app-picker/uninstall.sh
```

| Option | Effect |
|---|---|
| *(none)* | Asks first; removes the plugin, bar icon and keybinding block; keeps favorites and settings |
| `--purge` | Also deletes `~/.local/state/omarchy-app-picker.json` |
| `--yes` | Don't ask |
| `--no-restart` | Don't restart the shell |

The uninstaller backs up `bindings.lua` before removing its block. Bindings
you added yourself are not touched.

## 7. Moving favorites to another machine

Copy `~/.local/state/omarchy-app-picker.json` to the same path on the other
machine, then restart the shell (`omarchy restart shell`). Favorites are
stored by desktop-entry id, so they match wherever the same apps are
installed.

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `[FAIL] 'omarchy-shell' not found` | Not an Omarchy 4 system | The App Picker needs Omarchy 4 or later |
| `[FAIL] The Omarchy shell is not running` | Run from SSH or a TTY, or the shell crashed | Run it in a terminal on the Omarchy desktop, or start the shell with `omarchy restart shell` |
| `[WARN] "SUPER + A" is already bound to "…"` | Another action uses the key | Re-run with a free key (`--key`) or take it (`--force-key`) |
| `[FAIL] … already exists. Replace it? Re-run with --yes` | Run without a terminal over an existing install | Re-run with `--yes` |
| Shortcut does nothing | Bind not loaded or config error | `hyprctl reload`, then `hyprctl configerrors`; check `hyprctl binds` |
| Bar icon missing | Plugin not enabled | `omarchy plugin enable mulcahyio.app-picker --section left --after omarchy.menu` |
| A change to the plugin files doesn't show | Shell keeps the loaded plugin | `omarchy restart shell` |
| `git clone` asks for a password / "Repository not found" | No access to the private repository | Log in with `gh auth login` using an account that has access |

Still stuck? Contact dev@mulcahy.io with the output of `./install.sh`,
`omarchy version` and `hyprctl version`.
