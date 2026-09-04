const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const qmlPath = path.join(root, "plugins/monitor/monitor.qml");
const backendPath = path.join(root, "plugins/monitor/backend");
const manifestPath = path.join(root, "plugins/monitor/plugin.json");

function source(file) { return fs.readFileSync(file, "utf8"); }

test("monitor manifest and backend are plugin-local", () => {
  const manifest = JSON.parse(source(manifestPath));
  assert.equal(manifest.key, "monitor");
  assert.equal(manifest.ui, "monitor.qml");
  assert.match(source(backendPath), /^#!\/bin\/bash/);
});

test("monitor uses plugin-exec for snapshot, detail and kill", () => {
  const qml = source(qmlPath);
  assert.match(qml, /root\.run\(\["plugin-exec",\s*pluginKey,\s*"snapshot"/);
  assert.match(qml, /root\.run\(\["plugin-exec",\s*pluginKey,\s*"detail"/);
  assert.match(qml, /root\.run\(\["plugin-exec",\s*pluginKey,\s*"kill"/);
});

test("monitor implements keyboard navigation, filter editing and modal escape", () => {
  const qml = source(qmlPath);
  assert.match(qml, /property bool keyboardNavigationBlocked:\s*filterField\.activeFocus\s*$/m);
  assert.match(qml, /function handleKeyboardAction\(action, payload\)/);
  assert.match(qml, /action === "move"/);
  assert.match(qml, /action === "activate"/);
  assert.match(qml, /action === "delete"/);
  assert.match(qml, /action === "text"/);
  assert.match(qml, /action === "back"/);
  assert.match(qml, /filterField\.forceActiveFocus\(\)/);
  assert.match(qml, /id:\s*filterField[\s\S]*Keys\.onEscapePressed:[\s\S]*filterField\.focus\s*=\s*false[\s\S]*event\.accepted\s*=\s*true/);
  assert.match(qml, /Shortcut\s*\{[\s\S]*sequence:\s*"Escape"[\s\S]*enabled:\s*detailVisible\s*\|\|\s*confirmVisible[\s\S]*onActivated:\s*cancelOverlay\(\)/);
  assert.match(qml, /selectedPid/);
});

test("monitor exposes animated rolling graphs and mouse process actions", () => {
  const qml = source(qmlPath);
  assert.match(qml, /cpuHistory/);
  assert.match(qml, /ramHistory/);
  assert.match(qml, /Canvas/);
  assert.match(qml, /Behavior on/);
  assert.match(qml, /MouseArea/);
  assert.match(qml, /openDetail\(/);
  assert.match(qml, /openConfirmation\(/);
});

test("kill confirmation is visible from the list and preserves the chosen signal", () => {
  const qml = source(qmlPath);
  assert.match(qml, /visible:\s*detailVisible\s*\|\|\s*confirmVisible/);
  assert.match(qml, /function openConfirmation\(pid, choice\)/);
  assert.match(qml, /openConfirmation\(detailData\.pid,\s*actionChoice\)/);
});

test("monitor samples only while its active panel is open and updates notch status", () => {
  const qml = source(qmlPath);
  assert.match(qml, /property bool pluginVisible:/);
  assert.match(qml, /Timer\s*\{[\s\S]*running:\s*root\s*&&\s*root\.opened\s*&&\s*monitor\.pluginVisible/);
  assert.match(qml, /root\.updateNotchData\(pluginKey,\s*notchIcon,\s*notchText\)/);
});
