const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const pluginKeys = ["markets", "monitor", "news"];

for (const key of pluginKeys) {
  test(`${key} is a self-contained keyboard-first plugin`, () => {
    const dir = path.join(repoRoot, "plugins", key);
    const manifestPath = path.join(dir, "plugin.json");
    const qmlPath = path.join(dir, `${key}.qml`);
    const backendPath = path.join(dir, "backend");

    assert.ok(fs.existsSync(manifestPath), `${key}: missing plugin.json`);
    assert.ok(fs.existsSync(qmlPath), `${key}: missing ${key}.qml`);
    assert.ok(fs.existsSync(backendPath), `${key}: missing backend`);
    assert.ok(fs.statSync(backendPath).mode & 0o111, `${key}: backend is not executable`);

    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    assert.equal(manifest.key, key);
    assert.equal(manifest.ui, `${key}.qml`);
    assert.ok(manifest.label?.en && manifest.label?.es, `${key}: bilingual label required`);

    const qml = fs.readFileSync(qmlPath, "utf8");
    assert.match(qml, /property bool keyboardNavigationBlocked:/);
    assert.match(qml, /function handleKeyboardAction\(action, payload\)/);
    for (const action of ["move", "activate", "delete", "text", "back"])
      assert.match(
        qml,
        new RegExp(`(?:action === ["']${action}["']|case ["']${action}["'])`),
        `${key}: missing ${action} keyboard action`,
      );
    assert.match(qml, /plugin-exec/);
    assert.match(qml, /pluginKey/);
  });
}

test("plugin tab orders are unique and deterministic", () => {
  const manifests = fs.readdirSync(path.join(repoRoot, "plugins"), { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name !== "_template")
    .map((entry) => JSON.parse(fs.readFileSync(path.join(repoRoot, "plugins", entry.name, "plugin.json"), "utf8")));
  const orders = manifests.map((manifest) => manifest.order);
  assert.equal(new Set(orders).size, orders.length, "Every plugin needs a unique order");
});
