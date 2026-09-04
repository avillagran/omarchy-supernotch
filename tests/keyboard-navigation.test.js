const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const repoRoot = path.resolve(__dirname, "..");

function loadNavigation() {
  const source = fs.readFileSync(path.join(repoRoot, "KeyboardNavigation.js"), "utf8");
  const context = {};
  vm.createContext(context);
  vm.runInContext(source, context, { filename: "KeyboardNavigation.js" });
  return context;
}

test("dispatch sends a semantic action only to the active plugin", () => {
  const navigation = loadNavigation();
  const calls = [];
  const inactive = { handleKeyboardAction() { calls.push("inactive"); } };
  const active = {
    handleKeyboardAction(action, payload) {
      calls.push({ action, payload });
      return true;
    },
  };

  const plugin = navigation.activePlugin([inactive, active], 1);
  const handled = navigation.dispatch(plugin, "move", { dx: -1, dy: 0 });

  assert.equal(handled, true);
  assert.deepEqual(calls, [{ action: "move", payload: { dx: -1, dy: 0 } }]);
});

test("editing lock is read only from the active plugin", () => {
  const navigation = loadNavigation();
  const inactive = { keyboardNavigationBlocked: true };
  const active = { keyboardNavigationBlocked: false };

  assert.equal(navigation.isBlocked(navigation.activePlugin([inactive, active], 1)), false);
  active.keyboardNavigationBlocked = true;
  assert.equal(navigation.isBlocked(active), true);
});

test("Panel routes content actions through the keyboard contract", () => {
  const panel = fs.readFileSync(path.join(repoRoot, "Panel.qml"), "utf8");

  assert.match(panel, /import "KeyboardNavigation\.js" as KeyboardNavigation/);
  assert.match(panel, /activePluginItem:\s*KeyboardNavigation\.activePlugin\(root\.contentRefs, root\.current\)/);
  assert.match(panel, /blocked:\s*KeyboardNavigation\.isBlocked\(root\.activePluginItem\)/);
  assert.match(panel, /dispatchKeyboardAction\("move",\s*\{ dx: dx, dy: dy \}\)/);
  assert.match(panel, /dispatchKeyboardAction\("activate",\s*\{\}\)/);
  assert.match(panel, /dispatchKeyboardAction\("delete",\s*\{\}\)/);
  assert.match(panel, /dispatchKeyboardAction\("text",\s*\{ text: t \}\)/);
});

test("Escape lets the active plugin go back before closing the panel", () => {
  const panel = fs.readFileSync(path.join(repoRoot, "Panel.qml"), "utf8");

  assert.match(
    panel,
    /onCloseRequested:\s*\{[\s\S]*focusSection === "content"[\s\S]*dispatchKeyboardAction\("back",\s*\{\}\)[\s\S]*root\.close\(\)[\s\S]*\}/,
  );
});

test("number shortcuts select a tab without toggling the panel closed", () => {
  const panel = fs.readFileSync(path.join(repoRoot, "Panel.qml"), "utf8");

  assert.match(panel, /if \(idx < root\.plugins\.length\)\s*\{\s*root\.setModule\(idx\)/);
  assert.doesNotMatch(panel, /if \(idx < root\.plugins\.length\)\s*\{\s*root\.openPlugin\(/);
});

test("keyboard catcher regains focus when a plugin editor releases it", () => {
  const panel = fs.readFileSync(path.join(repoRoot, "Panel.qml"), "utf8");
  const handler = panel.match(/onBlockedChanged:\s*\{([\s\S]*?)\n\s*\}/);
  assert.ok(handler, "PanelKeyCatcher must react when editing ends");
  assert.match(handler[1], /if \(!blocked && root\.opened\)[\s\S]*forceActiveFocus\(\)/);
  assert.doesNotMatch(handler[1], /Qt\.callLater/, "focus restoration must be synchronous to prevent CardWindow closing");
});

test("plugin author documentation defines the keyboard contract", () => {
  const readme = fs.readFileSync(path.join(repoRoot, "README.md"), "utf8");
  const template = fs.readFileSync(path.join(repoRoot, "plugins/_template/hello.qml"), "utf8");

  assert.match(readme, /keyboardNavigationBlocked/);
  assert.match(readme, /handleKeyboardAction/);
  assert.match(readme, /"move"/);
  assert.match(readme, /"activate"/);
  assert.match(readme, /"delete"/);
  assert.match(readme, /"text"/);
  assert.match(readme, /"back"/);
  assert.match(template, /property string pluginKey/);
});
