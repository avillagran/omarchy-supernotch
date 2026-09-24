const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
function source(relative) { return fs.readFileSync(path.join(root, relative), "utf8"); }

test("tasks opens directly in its input and supports keyboard completion", () => {
  const qml = source("plugins/tasks/tasks.qml");
  assert.match(qml, /onPluginVisibleChanged:[\s\S]*taskInput\.forceActiveFocus\(\)/);
  assert.match(qml, /id:\s*taskInput/);
  assert.match(qml, /function moveTaskSelection\(/);
  assert.match(qml, /function toggleSelectedTask\(/);
  assert.match(qml, /Qt\.Key_Space/);
  assert.match(qml, /Qt\.Key_Escape/);
  assert.match(qml, /root\.close\(\)/);
});

test("clock uses a packaged Equal Earth map with real country geometry", () => {
  const qml = source("plugins/clock/clock.qml");
  const map = source("assets/world-equal-earth.svg");
  const notice = source("assets/world-equal-earth.NOTICE");
  assert.match(qml, /id:\s*worldMap/);
  assert.match(qml, /function equalEarthPoint\(/);
  assert.match(qml, /world-equal-earth\.svg/);
  assert.match(map, /<path d=/);
  assert.match(notice, /Natural Earth/);
  assert.match(qml, /worldClocks/);
  assert.match(qml, /timeZoneRail/);
});

test("weather renders a real ECMWF pre-rendered chart with layer selector", () => {
  const qml = source("plugins/weather/weather.qml");
  const backend = source("plugins/weather/rust/src/main.rs");
  const mapRenderer = source("plugins/weather/rust/src/weather_map.rs");
  const launcher = source("plugins/weather/backend");
  assert.match(launcher, /supernotch-weather/);
  assert.match(launcher, /uname -m/);
  for (const arch of ["aarch64", "x86_64"]) {
    assert.ok(fs.existsSync(path.join(root, `plugins/weather/bin/${arch}/supernotch-weather`)), `missing ${arch} binary`);
  }
  const model = source("plugins/weather/Model.js");
  assert.match(qml, /property var chartData/);
  assert.match(qml, /function loadChart\(/);
  assert.match(qml, /setMapLayer/);
  assert.match(qml, /onActiveIdChanged:[\s\S]*loadChart\(\)/);
  assert.match(qml, /chartImage/);
  // The chart uses locally rendered forecast frames rather than remote tiles.
  assert.match(qml, /file:\/\/" \+ m\.currentFrame\.path/);
  assert.match(backend, /fn render_chart\(/);
  assert.match(backend, /ecmwf_ifs025/);
  assert.match(backend, /fn fetch_ifs_grid\(/);
  assert.match(mapRenderer, /COASTLINES_GEOJSON/);
  assert.match(mapRenderer, /ECMWF IFS · Open-Meteo CC-BY-4.0/);
  assert.match(model, /precipitation/);
});

test("markets use a Nerd Font star on favorite assets without a favorites tile", () => {
  const qml = source("plugins/markets/markets.qml");
  assert.match(qml, /favorite \? "󰓎" : "󰓏"/);
  assert.doesNotMatch(qml, /text:\s*"FAVORITES\s*·/);
});

test("monitor preserves selection by PID and avoids an initial polling delay", () => {
  const qml = source("plugins/monitor/monitor.qml");
  assert.match(qml, /function restoreSelection\(pid\)/);
  assert.match(qml, /restoreSelection\(keepPid\)/);
  assert.match(qml, /triggeredOnStart:\s*true/);
});
