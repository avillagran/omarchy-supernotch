const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const qmlPath = path.join(repoRoot, "plugins/weather/weather.qml");
const backendPath = path.join(repoRoot, "plugins/weather/backend");

function source(file) { return fs.readFileSync(file, "utf8"); }

test("weather is a plugin-local multi-city feature using the root.run helper contract", () => {
  const qml = source(qmlPath);
  assert.match(source(backendPath), /^#!\/usr\/bin\/env python3/);
  for (const command of ["state", "search", "forecast", "add-city", "replace-city", "activate", "reorder", "remove"])
    assert.match(qml, new RegExp(`\\["${command}"`), `missing ${command} helper call`);
  assert.match(qml, /root\.run\(\["plugin-exec",\s*pluginKey\]\.concat\(args\)/);
  assert.doesNotMatch(qml, /root\.run\(\["weather-(?:state|fetch)"/);
});

test("city label edits the current city while the plus card adds another", () => {
  const qml = source(qmlPath);
  assert.match(qml, /function beginEditCity\(\)/);
  assert.match(qml, /onClicked:\s*m\.beginEditCity\(\)/);
  assert.match(qml, /function beginAddCity\(\)/);
  assert.match(qml, /id:\s*addMouse[\s\S]*onClicked:\s*m\.beginAddCity\(\)/);
  assert.match(qml, /searchPurpose\s*===\s*"edit"/);
  assert.match(qml, /tr\("Edit city",\s*"Editar ciudad"\)/);
  assert.match(qml, /tr\("Add city",\s*"Agregar ciudad"\)/);
});

test("city label becomes a debounced autocomplete that drops stale responses", () => {
  const qml = source(qmlPath);
  assert.match(qml, /id:\s*searchField/);
  assert.match(qml, /id:\s*searchDebounce[\s\S]*interval:\s*250/);
  assert.match(qml, /searchField\.text\.trim\(\)\.length\s*<\s*2/);
  assert.match(qml, /Model\.responseIsCurrent\((?:m\.)?requestTokens,\s*"search",\s*requestId\)/);
  assert.match(qml, /modelData\.displayName|JSON\.stringify\(suggestion\)/);
  assert.match(qml, /modelData\.region/);
  assert.match(qml, /modelData\.country/);
});

test("weather keeps independent city loading and errors and only polls the active visible tab", () => {
  const qml = source(qmlPath);
  assert.match(qml, /readonly property bool pluginVisible:\s*root\s*&&\s*root\.opened\s*&&\s*visible\s*&&\s*root\.activePluginItem\s*===\s*m/);
  assert.match(qml, /Model\.updateCityRuntime\(cities,\s*city\.id,\s*\{\s*loading:\s*true,\s*error:\s*""\s*\}\)/);
  assert.match(qml, /Model\.responseIsCurrent\((?:m\.)?requestTokens,\s*city\.id,\s*requestId\)/);
  assert.match(qml, /loading:\s*false,\s*error:/);
  assert.match(qml, /Timer\s*\{[\s\S]*running:\s*m\.pluginVisible[\s\S]*onTriggered:\s*m\.refreshAll\(\)/);
  assert.match(qml, /function refreshAll\(\)\s*\{\s*if \(!pluginVisible\) return/);
});

test("compact cards select the active notch city and expose full keyboard management", () => {
  const qml = source(qmlPath);
  assert.match(qml, /model:\s*m\.cities/);
  assert.match(qml, /modelData\.weather\.icon/);
  assert.match(qml, /modelData\.weather\.temp/);
  assert.match(qml, /modelData\.name/);
  assert.match(qml, /activeId/);
  assert.match(qml, /updateNotchData\(pluginKey,\s*active\.weather\.icon/);
  assert.match(qml, /property bool keyboardNavigationBlocked:\s*searchField\.activeFocus/);
  assert.match(qml, /function handleKeyboardAction\(action, payload\)/);
  for (const action of ["move", "activate", "delete", "text", "back"])
    assert.match(qml, new RegExp(`action === "${action}"`));
  assert.match(qml, /beginRemoveConfirmation/);
  assert.match(qml, /confirmNearby/);
  assert.match(qml, /tr\("Remove city\?",\s*"¿Eliminar ciudad\?"\)/);
  assert.match(qml, /text\s*===\s*"e"[^\n]*beginEditCity\(\)/);
  assert.match(qml, /E edit/);
  assert.match(qml, /A add/);
  assert.match(qml, /U\/D reorder/);
});

test("weather reserves enough responsive panel height for cards and autocomplete", () => {
  const qml = source(qmlPath);
  const manifest = JSON.parse(source(path.join(repoRoot, "plugins/weather/plugin.json")));
  assert.ok(manifest.preferredHeight >= 430);
  assert.match(qml, /implicitHeight:\s*Style\.space\(430\)/);
});

test("weather bindings never dereference a missing active city", () => {
  const qml = source(qmlPath);
  assert.doesNotMatch(qml, /Text\s*\{[^\n]*text:[^\n]*m\.activeCity\(\)\.weather/);
  assert.doesNotMatch(qml, /m\.searchField/);
});

test("weather derives forecast days from the city's local report date", () => {
  const qml = source(qmlPath);
  assert.match(qml, /function reportDate\(report\)/);
  assert.match(qml, /report\.current\.time/);
  assert.match(qml, /Model\.cityWeather\(report,\s*m\.reportDate\(report\)\)/);
});

test("weather cancels search mode when its tab becomes inactive", () => {
  const qml = source(qmlPath);
  assert.match(qml, /onPluginVisibleChanged:\s*\{\s*if \(pluginVisible\) loadState\(true\)\s*else cancelOverlay\(\)\s*\}/);
});
