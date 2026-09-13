import QtQuick
import Quickshell.Io

// SuperNotch service: installs the SUPER+SHIFT+N keybind on enable.
// Services load with no user gesture, so this is the only place a plugin can
// run a process at startup (G15). The helper writes supernotch-bindings.lua
// and appends its require to hyprland.lua; Hyprland auto-reloads on write.
// The helper path is resolved relative to this file (the plugin dir), which
// is reliable whether the plugin is symlinked or copied into the user config.
Item {
  id: root

  readonly property string helper: {
    var dir = Qt.resolvedUrl(".").toString().replace("file://", "")
    if (dir && dir.length > 0) return dir.replace(/\/$/, "") + "/bin/omarchy-supernotch"
    return ""
  }

  Process {
    running: root.helper !== ""
    command: [root.helper, "install-bind"]
  }

  // Keep a plugin-owned watch process alive so the Clipboard panel receives
  // new Wayland text selections even while the panel itself is closed.
  Process {
    running: root.helper !== ""
    command: [root.helper, "clip-watch"]
  }
}
