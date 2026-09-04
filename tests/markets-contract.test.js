const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const qmlPath = path.join(repoRoot, "plugins", "markets", "markets.qml");
const metadataPath = path.join(repoRoot, "plugins", "markets", "plugin.json");

function qml() { return fs.readFileSync(qmlPath, "utf8"); }

test("Markets declares a discoverable localized plugin", () => {
  const metadata = JSON.parse(fs.readFileSync(metadataPath, "utf8"));
  assert.equal(metadata.key, "markets");
  assert.equal(metadata.ui, "markets.qml");
  assert.equal(metadata.label.en, "Markets");
  assert.equal(metadata.label.es, "Mercados");
  assert.match(metadata.icon, /\S/);
});

test("Markets follows the plugin backend and visibility-scoped refresh contracts", () => {
  const source = qml();
  assert.match(source, /root\.run\(\["plugin-exec",\s*pluginKey\]\.concat\(args\)/);
  assert.match(source, /Timer\s*\{[\s\S]*?running:\s*m\.visible\s*&&\s*root\s*&&\s*root\.opened[\s\S]*?onTriggered:\s*m\.refreshMarkets\(false\)/);
  assert.match(source, /root\.updateNotchData\(pluginKey,\s*m\.notchIcon,\s*m\.notchText\)/);
  assert.doesNotMatch(source, /notchPlugins|notchList/);
});

test("Markets exposes list detail form and confirmation keyboard modes", () => {
  const source = qml();
  assert.match(source, /property string mode:\s*"list"/);
  assert.match(source, /function handleKeyboardAction\(action,\s*payload\)/);
  for (const action of ["move", "activate", "delete", "text", "back", "escape"]) {
    assert.match(source, new RegExp(`action\\s*===\\s*"${action}"`));
  }
  assert.match(source, /["']hjkl["']\.indexOf/);
  assert.match(source, /function moveListSelection/);
  assert.match(source, /function moveDetailSelection/);
  assert.match(source, /function moveFormSelection/);
  assert.match(source, /function requestRemoval/);
  assert.match(source, /function confirmRemoval/);
  assert.match(source, /detailSelection\s*>=\s*7[\s\S]*?requestRemoval\("lot"/);
  assert.match(source, /mode\s*=\s*"confirm"/);
  assert.match(source, /visible:\s*m\.mode\s*===\s*"confirm"/);
});

test("keyboard blocking is tied only to actual TextField focus", () => {
  const source = qml();
  const declaration = source.match(/property bool keyboardNavigationBlocked:\s*([^\n]+)/);
  assert.ok(declaration, "keyboardNavigationBlocked declaration missing");
  assert.match(declaration[1], /symbolField\.activeFocus/);
  assert.match(declaration[1], /quantityField\.activeFocus/);
  assert.match(declaration[1], /dateField\.activeFocus/);
  assert.match(declaration[1], /priceField\.activeFocus/);
  assert.doesNotMatch(declaration[1], /mode|loading|confirm/);
  assert.match(source, /Keys\.onEscapePressed:\s*function/);
});

test("rows, detail ranges, forms and destructive confirmations have mouse parity", () => {
  const source = qml();
  assert.match(source, /component Sparkline:\s*Canvas/);
  assert.match(source, /Sparkline\s*\{[\s\S]*?values:\s*modelData\.sparkline/);
  for (const range of ["1D", "1W", "1M", "3M", "1Y"]) assert.match(source, new RegExp(`"${range}"`));
  assert.match(source, /onClicked:\s*m\.openDetail\(modelData\.symbol\)/);
  assert.match(source, /onTriggered:[^\n]*m\.reorderSelected\(-1\)/);
  assert.match(source, /onTriggered:[^\n]*m\.reorderSelected\(1\)/);
  assert.match(source, /onTriggered:\s*m\.openLotForm/);
  assert.match(source, /onTriggered:\s*m\.requestRemoval/);
  assert.match(source, /onTriggered:\s*m\.confirmRemoval/);
});

test("Markets renders loading error empty stale and portfolio states with theme tokens", () => {
  const source = qml();
  for (const word of ["Loading", "Unable", "watchlist", "cached", "Gain", "Cost basis"]) {
    assert.match(source, new RegExp(word, "i"));
  }
  assert.match(source, /Style\.fontFamily/);
  assert.doesNotMatch(source, /#[0-9a-fA-F]{3,8}|Qt\.rgba\(/);
});

test("the UI labels the unofficial provider and backend has query1/query2 fallback", () => {
  const source = qml();
  const backend = fs.readFileSync(path.join(repoRoot, "plugins", "markets", "backend"), "utf8");
  assert.match(source, /Yahoo Finance/i);
  assert.match(source, /unofficial|best.?effort/i);
  assert.match(backend, /query1\.finance\.yahoo\.com/);
  assert.match(backend, /query2\.finance\.yahoo\.com/);
});
