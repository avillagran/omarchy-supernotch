const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const helper = fs.readFileSync(path.join(repoRoot, "bin", "omarchy-supernotch"), "utf8");
const service = fs.readFileSync(path.join(repoRoot, "Service.qml"), "utf8");

test("clipboard recording has a persistent service-side Wayland watcher", () => {
  assert.match(helper, /clip-watch\)/, "helper must expose a persistent clipboard watcher command");
  assert.match(helper, /wl-paste\s+--type\s+text\s+--watch/, "watcher must receive text clipboard updates");
  assert.match(service, /command:\s*\[root\.helper,\s*"clip-watch"\]/, "service must start the watcher without opening the panel");
});

test("clipboard pause state is enforced by the watcher write boundary", () => {
  assert.match(helper, /clip_add\(\)[\s\S]*?clipEnabled/, "clip-add must check the persisted recording flag");
  assert.match(helper, /clip-set-enabled\)\s+write_pref\s+"clipEnabled"/, "panel toggle must persist the recording flag");
});
