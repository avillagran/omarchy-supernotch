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
  assert.match(qml, /action === "back"[^\n]*goBack\(\)/);
  assert.match(qml, /payload\.text === "j"/);
  assert.match(qml, /payload\.text === "k"/);
  assert.match(qml, /payload\.text === "h"/);
  assert.match(qml, /payload\.text === "l"/);
  assert.match(qml, /payload\.text === "x"/);
});

test("reader scrolls vertically by keyboard while horizontal keys choose actions", () => {
  const qml = source();
  assert.match(qml, /screen === "reader"[\s\S]*if \(dy\)[\s\S]*readerScroll\.scrollBy\([\s\S]*else if \(dx\)[\s\S]*readerAction/);
  assert.match(qml, /id:\s*readerKeyScroll[\s\S]*property:\s*"contentY"[\s\S]*Easing\.OutCubic/);
});

test("reader exposes original links only for cached built-in articles and opens by id", () => {
  const qml = source();
  assert.match(qml, /function canOpenExternal\(article\)/);
  assert.match(qml, /function readerActions\(\)/);
  assert.match(qml, /exec\(\["open", article\.id\]/);
  assert.doesNotMatch(qml, /exec\(\["open", article\.link\]/);
});

test("source chips scroll horizontally and reveal the keyboard-selected source", () => {
  const qml = source();
  assert.match(qml, /Flickable\s*\{\s*id:\s*sourceStrip[\s\S]*contentWidth:\s*sourceChips\.width[\s\S]*clip:\s*true/);
  assert.match(qml, /id:\s*sourceChips[\s\S]*width:\s*implicitWidth/);
  assert.match(qml, /function revealSelectedSource\(\)[\s\S]*sourceStrip/);
  assert.doesNotMatch(qml, /sources\.filter[\s\S]{0,100}\.slice\(0,\s*7\)/);
});

test("article viewport reserves the footer and shows complete rows", () => {
  const qml = source();
  assert.match(qml, /height:\s*parent\.height\s*-\s*Style\.space\(screen === "articles" \? 106 : 68\)/);
  assert.match(qml, /id:\s*articleList[\s\S]*height:\s*Style\.space\(70\)/);
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

test("News animates list, reader, sources, add and confirmation screens", () => {
  const qml = source();
  assert.ok((qml.match(/Behavior on opacity/g) || []).length >= 5);
  assert.ok((qml.match(/Behavior on scale/g) || []).length >= 5);
});
