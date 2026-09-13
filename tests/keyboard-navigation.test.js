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

// Execute the actual JS bodies in Panel.qml, not a duplicate of its logic.
function panelBody(source, marker) {
  const markerIndex = source.indexOf(marker);
  assert.notEqual(markerIndex, -1, `missing ${marker}`);
  const start = source.indexOf("{", markerIndex + marker.length);
  let depth = 1;
  let end = start + 1;
  for (; end < source.length && depth; end++) {
    if (source[end] === "{") depth++;
    if (source[end] === "}") depth--;
  }
  assert.equal(depth, 0, `unclosed ${marker}`);
  return source.slice(start + 1, end - 1);
}

function loadPanel() {
  const source = fs.readFileSync(path.join(repoRoot, "Panel.qml"), "utf8");
  const navigation = loadNavigation();
  const root = {
    current: 0, _pending: 0, focusSection: "tabs", opened: true,
    contentOpacity: 1, cardH: 360, fullH: 480, plugins: [{}, {}, {}, {}],
    contentRefs: [], pushBar() {},
  };
  Object.defineProperty(root, "activePluginItem", {
    get() { return navigation.activePlugin(root.contentRefs, root.current); },
  });
  const context = vm.createContext({ root, KeyboardNavigation: navigation });
  function handler(marker, args = "") {
    return vm.runInContext(`(function(${args}) {${panelBody(source, marker)}\n})`, context);
  }
  root.close = handler("function close()");
  root.dispatchKeyboardAction = handler("function dispatchKeyboardAction(", "action, payload");
  return { root, handler, context, source };
}

for (const focusSection of ["tabs", "content"]) {
  test(`Escape offers back from ${focusSection} and closes only when unconsumed`, () => {
    const { root, handler } = loadPanel();
    root.focusSection = focusSection;
    const calls = [];
    let inDetail = true; // e.g. a reader opened by mouse while tabs retain focus
    root.contentRefs = [{
      handleKeyboardAction(action) {
        calls.push(action);
        if (!inDetail) return false;
        inDetail = false;
        return true;
      },
    }, { handleKeyboardAction() { assert.fail("inactive plugin received Escape"); } }];
    const escape = handler("onCloseRequested:");
    escape();
    assert.deepEqual(calls, ["back"]);
    assert.equal(root.opened, true);
    escape();
    assert.deepEqual(calls, ["back", "back"]);
    assert.equal(root.opened, false);
  });
}

test("Escape closes when the active plugin is absent or has no keyboard handler", () => {
  for (const plugin of [null, {}]) {
    const { root, handler } = loadPanel();
    root.contentRefs = [plugin];
    handler("onCloseRequested:")();
    assert.equal(root.opened, false);
  }
});

function loadSwitchingPanel() {
  const panel = loadPanel();
  const { root, handler, context, source } = panel;
  // Fake only Qt's clock; execute the real setModule, key and timer handlers.
  const timerSource = source.slice(source.indexOf("id: switchTimer;"));
  const interval = Number(timerSource.match(/interval:\s*(\d+)/)[1]);
  let now = 0;
  let deadline = null;
  const timer = {
    get running() { return deadline !== null; },
    start() { if (!this.running) deadline = now + interval; },
    restart() { deadline = now + interval; },
  };
  context.switchTimer = timer;
  root.setModule = handler("function setModule(", "i");
  const triggered = vm.runInContext(`(function() {${panelBody(timerSource, "onTriggered:")}\n})`, context);
  return {
    ...panel, interval,
    tab: handler("onTabRequested:", "d"),
    move: handler("onMoveRequested:", "dx, dy"),
    text: handler("onTextKey:", "t"),
    advance(ms) {
      const target = now + ms;
      if (deadline !== null && deadline <= target) {
        now = deadline;
        deadline = null; // a non-repeating Qt Timer stops before onTriggered
        triggered();
      }
      now = target;
    },
  };
}

for (const [key, direction] of [["Tab", 1], ["ShiftTab", -1], ["Right", 1], ["Left", -1]]) {
  test(`two rapid ${key} events accumulate their pending destination`, () => {
    const p = loadSwitchingPanel();
    const press = () => key.includes("Tab") ? p.tab(direction) : p.move(direction, 0);
    press();
    press();
    assert.equal(p.root.current, 0, "switch still waits for the fade");
    p.advance(p.interval);
    assert.equal(p.root.current, 2);
    assert.equal(p.root.contentOpacity, 1);
    assert.equal(p.root.cardH, p.root.fullH);
  });
}

test("mixed rapid directions can return to the currently displayed tab", () => {
  const p = loadSwitchingPanel();
  p.tab(1);
  p.move(1, 0);
  p.tab(-1);
  p.move(-1, 0);
  p.advance(p.interval);
  assert.equal(p.root.current, 0);
  assert.equal(p.root.contentOpacity, 1);
});

test("continuous keys do not postpone the original switch deadline", () => {
  const p = loadSwitchingPanel();
  p.tab(1);
  p.advance(p.interval - 1);
  p.tab(1);
  p.advance(1);
  assert.equal(p.root.current, 2, "first transition must finish at its original deadline");
  p.tab(1);
  p.advance(p.interval - 1);
  p.move(1, 0);
  p.advance(1);
  assert.equal(p.root.current, 0, "the next transition also progresses under input");
});

test("an absolute shortcut back to current overrides a pending switch", () => {
  const p = loadSwitchingPanel();
  p.tab(1);
  p.text("1");
  p.advance(p.interval);
  assert.equal(p.root.current, 0);
  assert.equal(p.root.contentOpacity, 1);
  assert.equal(p.root.opened, true);
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
