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
  assert.match(source, /readonly property bool pluginVisible:\s*root\s*&&\s*root\.activePluginItem\s*===\s*m/);
  assert.match(source, /Timer\s*\{[\s\S]*?running:\s*m\.pluginVisible\s*&&\s*root\s*&&\s*root\.opened[\s\S]*?onTriggered:\s*m\.refreshMarkets\(false\)/);
  assert.match(source, /root\.updateNotchData\(pluginKey,\s*m\.notchIcon,\s*m\.notchText\)/);
  assert.doesNotMatch(source, /notchPlugins|notchList/);
});

test("Markets exposes pulse detail action form and confirmation keyboard modes", () => {
  const source = qml();
  assert.match(source, /property string mode:\s*"pulse"/);
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
  assert.match(source, /opacity:\s*m\.mode\s*===\s*"confirm"\s*\?\s*1\s*:\s*0/);
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

test("Markets asset input searches names and exposes keyboard-selectable results", () => {
  const source = qml();
  assert.match(source, /id:\s*searchTimer[\s\S]*interval:\s*\d+[\s\S]*onTriggered:\s*m\.searchAssets\(\)/);
  assert.match(source, /exec\(\["search",\s*query\]/);
  assert.match(source, /property var searchResults:/);
  assert.match(source, /property int searchSelection:/);
  assert.match(source, /Keys\.onDownPressed:[^\n]*moveSearchSelection\(1\)/);
  assert.match(source, /Keys\.onUpPressed:[^\n]*moveSearchSelection\(-1\)/);
  assert.match(source, /onAccepted:\s*\{\s*if \(m\.searchResults\.length > 0\) m\.chooseSearchResult\(m\.searchSelection\); else m\.searchAssets\(\)\s*\}/);
  assert.match(source, /function chooseSearchResult\(/);
  assert.match(source, /onClicked:\s*m\.chooseSearchResult\(index\)/);
});

test("rows, detail ranges, forms and destructive confirmations have mouse parity", () => {
  const source = qml();
  assert.match(source, /component Sparkline:\s*Canvas/);
  assert.match(source, /Sparkline\s*\{[\s\S]*?values:\s*modelData\.sparkline/);
  for (const range of ["1D", "1W", "1M", "1Y", "5Y"]) assert.match(source, new RegExp(`"${range}"`));
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

test("Market Pulse hub exposes favorites and currency-separated portfolio summaries", () => {
  const source = qml();
  assert.match(source, /property string mode:\s*"pulse"/);
  assert.match(source, /property var favorites:/);
  assert.match(source, /property var portfolioByCurrency:/);
  assert.match(source, /function toggleFavorite\(/);
  assert.match(source, /exec\(\["toggle-favorite",\s*selectedSymbol\]/);
  assert.match(source, /Favorites/i);
  assert.match(source, /Portfolio/i);
  assert.match(source, /model:\s*m\.portfolioByCurrency/);
});

test("Market Pulse follows cached snapshot with refresh without losing navigation context", () => {
  const source = qml();
  assert.match(source, /exec\(\["snapshot"\]/);
  assert.match(source, /exec\(refreshArgs,/);
  assert.match(source, /function captureViewContext\(/);
  assert.match(source, /function restoreViewContext\(/);
  assert.match(source, /selectedSymbol/);
  assert.match(source, /contentY/);
});

test("Market Pulse offers a responsive hub to asset to action route", () => {
  const source = qml();
  assert.match(source, /readonly property bool compact:/);
  assert.match(source, /property string mode:\s*"pulse"/);
  assert.match(source, /function openDetail\(/);
  assert.match(source, /function openActions\(/);
  assert.match(source, /m\.mode === "action"/);
  assert.match(source, /Watchlist/);
  assert.match(source, /Record purchase/);
});

test("Market Pulse surfaces freshness provenance and reduced-motion-aware focus", () => {
  const source = qml();
  for (const field of ["source", "asOf", "fetchedAt", "stale", "marketState", "currency"])
    assert.match(source, new RegExp(`\\.${field}\\b`), field);
  assert.match(source, /readonly property bool reducedMotion:/);
  assert.match(source, /duration:\s*m\.motionDuration/);
  assert.match(source, /border\.color:\s*[^\n]*Color\.accent/);
});

test("Market Pulse keeps keyboard guidance visible in compact panels", () => {
  const source = qml();
  assert.match(source, /text:\s*m\.compact\s*\?\s*"↑\/↓ · Enter · x"/);
  assert.doesNotMatch(source, /visible:\s*!m\.compact;\s*text:\s*"↑\/↓ navigate/);
});

test("Market Pulse labels partial portfolio totals", () => {
  const source = qml();
  assert.match(source, /property bool portfolioComplete:/);
  assert.match(source, /property var unavailablePositions:/);
  assert.match(source, /portfolioComplete\s*=\s*result\.portfolioComplete/);
  assert.match(source, /Portfolio totals incomplete/);
});

test("Market Pulse distinguishes cached content from the initial loading state", () => {
  const source = qml();
  assert.match(source, /parseResult\(cachedOut,[\s\S]*?m\.loading\s*=\s*false[\s\S]*?m\.applyPulse\(cached, context\)/);
  assert.match(source, /loading\s*\?\s*"Loading…"\s*:\s*"Refreshing…"/);
});

test("ordinary Market Pulse opens do not force provider refreshes", () => {
  const source = qml();
  assert.match(source, /var refreshArgs = \["refresh"\]/);
  assert.match(source, /if \(force\) refreshArgs\.push\("--force"\)/);
  assert.match(source, /exec\(refreshArgs,/);
});

test("Market Pulse never exposes the raw UNKNOWN market-state sentinel", () => {
  const source = qml();
  assert.match(source, /function marketStateLabel\(/);
  assert.doesNotMatch(source, /asset\.marketState\s*\|\|\s*"UNKNOWN"/);
});

test("Market Pulse keeps refreshes from retargeting details or destructive actions", () => {
  const source = qml();
  assert.match(source, /function restoreViewContext\(context\)\s*\{\s*if \(!context \|\| mode !== "pulse"\) return/);
  assert.match(source, /function invalidateRefresh\(\)/);
  assert.match(source, /function mutate\([\s\S]*?invalidateRefresh\(\)/);
  assert.match(source, /function toggleFavorite\([\s\S]*?invalidateRefresh\(\)/);
  assert.match(source, /function reorderSelected\([\s\S]*?invalidateRefresh\(\)/);
  assert.match(source, /remove-symbol",\s*removalSymbol,\s*"confirm"/);
  assert.match(source, /remove-lot",\s*removalSymbol,\s*removalId/);
  assert.doesNotMatch(source, /selectedSymbol\s*\|\|\s*removalLabel/);
});

test("Market detail drops chart responses that arrive out of order", () => {
  const source = qml();
  assert.match(source, /property int chartGeneration:/);
  assert.match(source, /var generation = \+\+chartGeneration/);
  assert.match(source, /if \(generation !== chartGeneration\) return/);
});

test("Market detail uses chart-specific provenance and visible errors", () => {
  const source = qml();
  assert.match(source, /property var chartMetadata:/);
  assert.match(source, /property string chartError:/);
  assert.match(source, /result\.symbol !== selectedSymbol \|\| result\.range !== selectedRange/);
  assert.match(source, /provenanceText\(m\.chartMetadata\)/);
  assert.match(source, /visible:\s*m\.chartError !== ""/);
});

test("the UI labels the unofficial provider and backend has query1/query2 fallback", () => {
  const source = qml();
  const backend = fs.readFileSync(path.join(repoRoot, "plugins", "markets", "backend"), "utf8");
  assert.match(source, /Yahoo Finance/i);
  assert.match(source, /unofficial|best.?effort/i);
  assert.match(backend, /query1\.finance\.yahoo\.com/);
  assert.match(backend, /query2\.finance\.yahoo\.com/);
});

test("Markets animates every screen transition", () => {
  const source = qml();
  assert.ok((source.match(/Behavior on opacity/g) || []).length >= 4);
  assert.ok((source.match(/Behavior on scale/g) || []).length >= 4);
});

test("keyboard selection scrolls asset and lot rows into view", () => {
  const source = qml();
  assert.match(source, /id:\s*assetScroll[\s\S]*id:\s*assetScrollAnim[\s\S]*property:\s*"contentY"/);
  assert.match(source, /id:\s*lotScroll[\s\S]*id:\s*lotScrollAnim[\s\S]*property:\s*"contentY"/);
  assert.match(source, /function revealAssetSelection\(\)[\s\S]*assetScrollAnim\.start\(\)/);
  assert.match(source, /function revealLotSelection\(\)[\s\S]*lotScrollAnim\.start\(\)/);
  assert.match(source, /function moveListSelection[\s\S]*revealAssetSelection\(\)/);
  assert.match(source, /function moveDetailSelection[\s\S]*revealLotSelection\(\)/);
});
