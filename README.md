# SuperNotch

An **Anclave-style** animated notch for [Omarchy](https://github.com/basecamp/omarchy) (Arch/Hyprland).
A tiny center pill on the bar **blooms** into a dark, rounded, glassy command center — like the
Dynamic Island, but for your Linux desktop. Heavily animated, theme-aware, multi-language.

> Omarchy has no hardware notch, so SuperNotch simulates it: a centered bar pill that expands into a
> top-center card (anchored with `KeyboardPanel` + `centerOnBar`). The external window is your actual media
> player, tasks file, clipboard and shelf — SuperNotch only reads and controls them.

## Plugin system (the important part)

SuperNotch is a **plugin framework**, not a fixed set of tabs. Every tab is a folder under `plugins/`:

```
plugins/
  music/      plugin.json + music.qml     ← 🎵 Música
  tasks/      plugin.json + tasks.qml     ← ✓ Tareas
  clipboard/  plugin.json + clipboard.qml ← 📋 Portapapeles
  _template/  plugin.json + hello.qml     ← copy this to start a new one
```

Each plugin is loaded automatically (no core changes). To **add your own tab**, copy the template:

```bash
cp -r plugins/_template plugins/mything
# edit plugins/mything/plugin.json  → set key, icon, label{en,es}, ui
# edit plugins/mything/mything.qml → your UI
omarchy plugin reload   # or restart the shell
```

`plugin.json`:
```json
{
  "key": "mything",
  "icon": "✦",
  "label": { "en": "My Thing", "es": "Mi Cosa" },
  "ui": "mything.qml",
  "refresh": ["mything-data"]      // helper commands run on open (optional)
}
```

`mything.qml` receives `root` (the Panel) and `pluginKey` (its manifest key). Use:
- `root.run(["helper-cmd", arg], function(out){ /* out = stdout */ })` — run a shell command.
- `root.t(root.uiLang, "key")` — translate a string.
- `root.uiLang` — `"en"` | `"es"`.
- `Color.*` / `Style.*` — **theme tokens only; never hardcode colors.**

### Optional keyboard contract

Plugins can opt into keyboard navigation by exposing `handleKeyboardAction(action, payload)`. The Panel calls it only on the active plugin while keyboard focus is in the content area:

```qml
Item {
  property var root: null
  property string pluginKey: ""
  property int selectedIndex: 0

  // Bind this to every inline editor that must receive raw key events.
  property bool keyboardNavigationBlocked: editor.activeFocus

  function handleKeyboardAction(action, payload) {
    if (action === "move") {
      // payload.dx/payload.dy are -1, 0 or 1 (arrows and h/j/k/l).
      selectedIndex = Math.max(0, selectedIndex + payload.dy)
      return true
    }
    if (action === "activate") { activate(selectedIndex); return true } // Enter or Space
    if (action === "delete") { remove(selectedIndex); return true }     // x or X
    if (action === "text") { search += payload.text; return true }      // other one-character keys
    return false
  }

  TextField { id: editor }
}
```

Return `true` when an action was consumed. An unhandled upward `"move"` returns keyboard focus to the tabs; other unhandled actions are ignored. The contract is optional, so plugins without the function keep working and remain clickable.

`keyboardNavigationBlocked` is also optional and defaults to `false`. While it is `true`, `PanelKeyCatcher` does not consume any key, allowing the focused editor to receive text, arrows, Enter, Space, numbers, Tab and Esc normally. The editor should clear focus or set the property back to `false` when editing ends.

Outside editing, Panel-level controls remain reserved: Tab/Shift+Tab cycle tabs, Esc closes, and 1–9 select a tab. Arrow keys and h/j/k/l navigate tabs until focus enters content. Mouse clicks continue to work independently of this contract.

The panel handles the toolbar, the sliding active-tab indicator, the open/close bloom, crossfades,
and `centerOnBar` positioning. Your plugin just draws its content and calls `root.run(...)`.

Built-in plugins ship as examples: **Music** (MPRIS), **Tasks**, **Clipboard**. Add more — a weather
tab, a system monitor, a notes pad, anything — the same way.

## Animation

- The **pill blooms** on hover (eased) and the card **expands** from a small pill into the full panel.
- Module switches **crossfade**; the active tab indicator **slides**; the music progress bar animates.
- The card is a glass surface with a soft elevation, rounded corners, and the theme accent.

## Install

```bash
omarchy plugin add io.github.avillagran.omarchy-supernotch <git-url>
```

The plugin drops a `SUPER + SHIFT + N` keybind automatically. Or click the center pill in the bar.

## Usage

- **Click** the center pill (or `SUPER + SHIFT + N`) to open/close.
- **Click a tab** to switch plugins.
- **Tab/Shift+Tab** or **Left/Right** (`h`/`l`) switches tabs; **Down** (`j`) enters plugin content.
- **1–9** jumps directly to a tab.
- **Esc** closes the panel.

## Helper

`bin/omarchy-supernotch` is the local data engine. Try it:

```bash
omarchy-supernotch plugins-list        # list installed plugins
omarchy-supernotch mpris                # now-playing JSON
omarchy-supernotch clip-list            # clipboard history
omarchy-supernotch tasks-add "Ship SuperNotch"
```

## License

MIT
