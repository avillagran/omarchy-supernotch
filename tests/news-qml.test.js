const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const qmlPath = path.resolve(__dirname, "..", "plugins", "news", "news.qml");

function source() {
  return fs.readFileSync(qmlPath, "utf8");
}

test("News QML implements the panel keyboard contract", () => {
  const qml = source();
  assert.match(qml, /property bool keyboardNavigationBlocked:\s*[^\n]*activeFocus/);
  assert.match(qml, /function handleKeyboardAction\(action, payload\)/);
  assert.match(qml, /action === "move"/);
  assert.match(qml, /action === "activate"/);
  assert.match(qml, /action === "delete"/);
  assert.match(qml, /action === "text"/);
  assert.match(qml, /payload\.text === "j"/);
  assert.match(qml, /payload\.text === "k"/);
  assert.match(qml, /payload\.text === "h"/);
  assert.match(qml, /payload\.text === "l"/);
  assert.match(qml, /payload\.text === "x"/);
});

test("News QML routes every backend operation through plugin-exec", () => {
  const qml = source();
  assert.match(qml, /root\.run\(\["plugin-exec", pluginKey\]\.concat\(args\)/);
  assert.doesNotMatch(qml, /root\.run\(\["(?:news-|curl|wget|xdg-open)/);
});

test("News QML offers mouse actions for list, source, reader and confirmation screens", () => {
  const qml = source();
  assert.match(qml, /function openArticle\(/);
  assert.match(qml, /function activateSource\(/);
  assert.match(qml, /function confirmDelete\(/);
  assert.match(qml, /onClicked:\s*m\.openArticle/);
  assert.match(qml, /onClicked:[^\n]*m\.activateSource/);
  assert.match(qml, /onClicked:\s*m\.confirmDelete/);
  assert.match(qml, /onClicked:[^\n]*m\.activateCurrent/);
});

test("News refresh timer only runs for the visible plugin in an open panel", () => {
  const qml = source();
  assert.match(qml, /readonly property bool pluginVisible:\s*root\s*&&\s*root\.opened\s*&&\s*visible/);
  assert.match(qml, /Timer\s*\{[^}]*running:\s*m\.pluginVisible/s);
  assert.match(qml, /onPluginVisibleChanged:\s*if \(pluginVisible\)/);
});

test("News publishes a compact unread status to the notch", () => {
  const qml = source();
  assert.match(qml, /root\.updateNotchData\(pluginKey, notchIcon, notchText\)/);
  assert.match(qml, /property string notchIcon:/);
  assert.match(qml, /property string notchText:/);
});

test("News text fields release panel interception only while focused", () => {
  const qml = source();
  assert.match(qml, /property bool keyboardNavigationBlocked:\s*addUrlField\.activeFocus\s*\|\|\s*addNameField\.activeFocus\s*\|\|\s*filterField\.activeFocus/);
  assert.match(qml, /Keys\.onEscapePressed:/);
});
