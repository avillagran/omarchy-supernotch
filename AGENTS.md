# Agent Notes — omarchy-supernotch

## Pill layout rule (do not break)

The notch pill must always display enabled plugins **split to the LEFT and RIGHT of the center gap** whenever there is enough room:

```text
(  [1][2]  | Interior Notch  |  [3][4]  )
```

- `pill.enabledList.length` is the number of plugins assigned to the notch.
- `pill.usableW = pill.width - notchInset` is the horizontal space available for content.
- Use a compact per-item budget (~90 px) when deciding `showAll` so the side-by-side layout appears on the default 20 % width.
- If `usableW` is too small, fall back to the ticker (one item at a time centered next to the gap).
- Do NOT stack all items in the center by default.

## Persistent state

User settings are stored in `~/.local/state/omarchy-supernotch/prefs.json`. Do not use `$XDG_RUNTIME_DIR` for settings — that directory is wiped on logout.

## Keyboard focus

The card uses `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` while open so the compositor routes all keys to `PanelKeyCatcher`. Closing the panel releases focus.

## Icons and typography

Render plugin text and glyphs with `font.family: Style.fontFamily` so SuperNotch follows the font configured by Omarchy. Prefer glyphs the configured font can draw; do not hardcode another font family.
