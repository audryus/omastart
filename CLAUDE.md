# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

OmaStart (`audryus.omastart`) is an Omarchy 4 Quattro **bar-widget plugin** (Quickshell/QML) that provides a start menu plus a floating Settings window. There is no build step: the shell loads the QML files directly from the plugin directory. `manifest.json` declares the single entry point `BarWidget.qml`. `README.md` documents user-facing behavior in detail. Read it before changing a feature.

## Commands

```bash
make validate   # omarchy plugin validate .   (manifest/structure check)
make rescan     # omarchy-shell shell rescanPlugins   (pick up QML edits)
make restart    # omarchy restart shell
make log        # tail the current Quickshell log filtered to this plugin + ReferenceError/ERROR
make journal    # same filter over today's journal
```

To check a QML change, rescan or restart the shell, open the menu, then run `make log`. QML runtime errors appear only there.

There is no test suite. `System.js`, `MenuModel.js` and `Hotkeys.js` are pure logic with no imports and a `module.exports` guard at the bottom, so you can exercise them from node:

```bash
node -e 'const M=require("./MenuModel.js"); console.log(M.parseMenuJsonc("{...}"))'
```

Keep them free of QML/Quickshell dependencies. New functions must be added to the `module.exports` block to be reachable from node.

## Architecture

- **`BarWidget.qml`** is the root. It owns the bar button, shared state (`favorites`, persisted to `~/.local/state/omarchy/settings/omastart-favorites.json`), and two `LazyLoader`s:
  - the menu popup: a full-screen layer-shell `PanelWindow` with `WlrKeyboardFocus.Exclusive`, not an xdg-popup, so typing works even when the cursor is on the bar. It contains `MenuLeftPane` (search, apps A–Z, update row, Learn/Trigger/Style tree), `MenuRightPane` (places, favorites, mouse actions) and `MenuFooter` (Settings + system rows).
  - `Settings.qml`: a floating window whose pages (`General`, `Defaults`, `Printers`+`Discovery`, `Uninstall`, `Joystick`+`JoystickConfig`, `Hotkeys`+`HotkeyEdit`) are switched by `section`. Settings stays instantiated while `item.picking` is true, so child flows (zenity, discovery, joystick install) survive the window closing. Pages start scans and watchers on creation, which is why they are lazily loaded.
- **Menu data** comes from the upstream Omarchy menu definition merged live with the user's `~/.config/omarchy/extensions/omarchy-menu.jsonc`. `MenuModel.js` parses JSONC, merges, filters and builds guard scripts. `System.js` turns the merged `items`/`itemOrder` maps into rows for the tree, the apps list and the footer. Provider-backed entries are handed off to the official `omarchy.menu` through `omarchy-shell shell toggle omarchy.menu '<json>'`. This plugin runs alongside the official menu and never replaces it.
- **`Menu.qml` is an untouched upstream reference copy.** Nothing instantiates it. Do not edit it. Use it to see how the official menu does something.
- **Hotkeys** (`Hotkeys.js`) edits a managed block delimited by `MARK_BEGIN`/`MARK_END` markers inside the user's Lua bind config. Only that block is rewritten.
- **Joystick → RetroArch**:
  - `Joystick.qml` lists `/dev/input/js*` sticks. Identity is `vid:pid` + interface with deterministic numbering, stored in `joysticks.json`.
  - `JoystickConfig.qml` loads a schematic from `presets/*.qml`. Each preset exposes `activeKey` and a `buttons` list of `{key,label}`. To add one, also register it in the `presets` array in `JoystickConfig.qml`, which is kept alphabetical.
  - Input capture runs `joybind.py` (stdlib only), which prints one `BTN n` / `BTN h0up` / `AXIS ±n` line per invocation.
  - Saving writes a udev autoconfig profile to `autoconfig/`. Installing it copies the profile to `/usr/share/libretro/autoconfig/udev/` via polkit.
  - `joysticks.json` and `autoconfig/` are per-machine state and git-ignored. Never commit them.

## Conventions and gotchas

- Shell imports: `qs.Commons` (`Util`, `Color`, …) and `qs.Ui` (`BarWidget`, `BarIconButton`, …). Shell commands go through `Util.execDetached` with `Util.shellQuote` for every interpolated value.
- Load sibling QML or files by path with `Qt.resolvedUrl(...)`. A plain relative path like `"presets/X.qml"` resolves through the `qs:` module mapping and fails with `module "qs.Commons" is not installed`. To get a filesystem path, strip `file://` from the resolved URL, as `Joystick.qml` does.
- Same-directory QML components need no import. JS libraries are imported as `import "MenuModel.js" as MenuModel`.
- Some existing comments, including in the Makefile, are in Portuguese. Either language is fine.
- Commit messages use Conventional Commits (`feat:`, `fix:`, `perf:`, `docs:`, `chore:`, `refactor:`) with short lowercase subjects.
