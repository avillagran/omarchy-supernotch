const assert = require("node:assert/strict");
const { execFileSync, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const helper = path.join(root, "bin/omarchy-supernotch");

function near(actual, expected) {
  assert.equal(typeof actual, "number");
  assert.ok(Math.abs(actual - expected) < 0.02, `${actual} is not near ${expected}`);
}

test("world clocks carry exemplar city coordinates from the installed timezone database", (t) => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "supernotch-clock-map-"));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const state = path.join(home, ".local/state/omarchy-supernotch");
  fs.mkdirSync(state, { recursive: true });
  fs.writeFileSync(path.join(state, "prefs.json"), JSON.stringify({
    worldClocks: ["Europe/Copenhagen", "Asia/Kolkata", "America/New_York", "Etc/UTC"],
  }));
  const clocks = JSON.parse(execFileSync(helper, ["worldclock-list"], {
    env: { ...process.env, HOME: home }, encoding: "utf8", timeout: 10_000,
  }));
  const byZone = Object.fromEntries(clocks.map(clock => [clock.tz, clock]));
  near(byZone["Europe/Copenhagen"].latitude, 55.667);
  near(byZone["Europe/Copenhagen"].longitude, 12.583);
  near(byZone["Asia/Kolkata"].latitude, 22.533);
  near(byZone["Asia/Kolkata"].longitude, 88.367);
  near(byZone["America/New_York"].latitude, 40.714);
  near(byZone["America/New_York"].longitude, -74.006);
  assert.equal(byZone["Etc/UTC"].latitude, null);
  assert.equal(byZone["Etc/UTC"].longitude, null);
  assert.equal(clocks[0].local, true);
});

test("map markers use city coordinates and the SVG's painted bounds with a negative secondary color", () => {
  const qml = fs.readFileSync(path.join(root, "plugins/clock/clock.qml"), "utf8");
  assert.match(qml, /typeof modelData\.latitude === "number" && typeof modelData\.longitude === "number"/);
  assert.match(qml, /m\.equalEarthPoint\(modelData\.longitude, modelData\.latitude,\s*worldMapImage\.paintedWidth, worldMapImage\.paintedHeight\)/);
  assert.match(qml, /worldMapImage\.paintedWidth\) \/ 2 \+ point\.x/);
  assert.match(qml, /worldMapImage\.paintedHeight\) \/ 2 \+ point\.y/);
  assert.doesNotMatch(qml, /clockCoordinates\(/);
  assert.ok((qml.match(/color: modelData\.primary \? Color\.accent : Color\.urgent/g) || []).length >= 3);
});

test("city row, map marker and time legend select the primary city without stealing remove clicks", () => {
  const qml = fs.readFileSync(path.join(root, "plugins/clock/clock.qml"), "utf8");
  assert.match(qml, /function selectClock\(tz\)/);
  assert.match(qml, /root\.run\(\["worldclock-select", tz\]/);
  assert.ok((qml.match(/onClicked: m\.selectClock\(modelData\.tz\)/g) || []).length >= 3);
  assert.match(qml, /visible: !modelData\.local && clockHover\.containsMouse/);
  assert.match(qml, /onClicked: m\.removeClock\(modelData\.tz\)/);
  assert.ok((qml.match(/modelData\.primary \? Color\.accent : Color\.urgent/g) || []).length >= 3);
});

test("selecting a world clock persists its primary status without changing the system timezone", (t) => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "supernotch-clock-select-"));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const state = path.join(home, ".local/state/omarchy-supernotch");
  fs.mkdirSync(state, { recursive: true });
  const prefsPath = path.join(state, "prefs.json");
  fs.writeFileSync(prefsPath, JSON.stringify({ worldClocks: ["Europe/Copenhagen", "America/New_York"] }));
  const env = { ...process.env, HOME: home };
  const list = (...args) => JSON.parse(execFileSync(helper, args, { env, encoding: "utf8", timeout: 10_000 }));
  const initial = list("worldclock-list");
  assert.equal(initial[0].local, true);
  assert.equal(initial.filter(clock => clock.primary).length, 1);
  assert.equal(initial[0].primary, true);

  const selected = list("worldclock-select", "Europe/Copenhagen");
  assert.equal(selected.find(clock => clock.tz === "Europe/Copenhagen").primary, true);
  assert.equal(selected[0].local, true);
  assert.equal(selected[0].primary, false);
  assert.equal(selected.filter(clock => clock.primary).length, 1);
  assert.match(selected.find(clock => clock.primary).date, /^\d{4}-\d{2}-\d{2}$/);
  assert.equal(JSON.parse(fs.readFileSync(prefsPath, "utf8")).worldClockActive, "Europe/Copenhagen");
  assert.equal(list("worldclock-list").find(clock => clock.primary).tz, "Europe/Copenhagen");

  const invalid = spawnSync(helper, ["worldclock-select", "Asia/Tokyo"], { env, encoding: "utf8", timeout: 10_000 });
  assert.notEqual(invalid.status, 0);
  assert.equal(list("worldclock-list").find(clock => clock.primary).tz, "Europe/Copenhagen");
  const removed = list("worldclock-del", "Europe/Copenhagen");
  assert.equal(removed.find(clock => clock.primary).tz, initial[0].tz);
  assert.equal(removed.filter(clock => clock.primary).length, 1);
  assert.equal(JSON.parse(fs.readFileSync(prefsPath, "utf8")).worldClockActive, null);
});

test("primary clock controls the calendar date and notch time across timezones", () => {
  const qml = fs.readFileSync(path.join(root, "plugins/clock/clock.qml"), "utf8");
  assert.match(qml, /readonly property var primaryClock:/);
  assert.match(qml, /onPrimaryClockChanged:\s*\{\s*syncToday\(\);\s*pushNotch\(\)/);
  assert.match(qml, /var timeStr = primary && primary\.time \? primary\.time :/);
  assert.match(qml, /var d = m\.today/);
  assert.match(qml, /onDateChanged:\s*\{[\s\S]*?m\.loadClocks\(\)/);
  assert.match(qml, /text: Qt\.formatDate\(m\.today, "MMMM d"\)/);
});

test("world clocks run through a packaged native Rust backend", () => {
  const dispatch = fs.readFileSync(helper, "utf8");
  const launcher = fs.readFileSync(path.join(root, "plugins/clock/backend"), "utf8");
  const cargo = fs.readFileSync(path.join(root, "plugins/clock/rust/Cargo.toml"), "utf8");
  assert.match(dispatch, /worldclock-\*\)\s+plugin_exec clock "\$@"/);
  assert.doesNotMatch(dispatch, /tz_coords\(\)|worldclock_list\(\)/);
  assert.match(launcher, /exec "\$BIN" "\$@"/);
  assert.match(cargo, /name = "supernotch-clock"/);
  for (const arch of ["aarch64", "x86_64"])
    assert.ok(fs.statSync(path.join(root, "plugins/clock/bin", arch, "supernotch-clock")).size > 0);
});

test("world-clock search preserves separate backend lines and renders one selectable city per row", () => {
  const zones = execFileSync(helper, ["worldclock-zones", "America"], {
    encoding: "utf8", timeout: 10_000,
  }).trim().split("\n");
  assert.ok(zones.length >= 2, "the backend must return distinct search results");
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8");
  assert.match(panel, /SplitParser[^\n]*onRead[^\n]*collected \+= d \+ /,
    "the shared helper runner must restore the line separators stripped by SplitParser");
  const qml = fs.readFileSync(path.join(root, "plugins/clock/clock.qml"), "utf8");
  assert.match(qml, /id: zoneList[\s\S]*?model: m\.zoneMatches/);
  assert.match(qml, /onClicked: m\.addClock\(modelData\)/);
  assert.doesNotMatch(qml, /Flow\s*\{[\s\S]*?model: m\.zoneMatches/);
});

test("clock search results remain scrollable inside the available display height", () => {
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8");
  const qml = fs.readFileSync(path.join(root, "plugins/clock/clock.qml"), "utf8");
  assert.match(panel, /item\.pluginKey === "clock"[\s\S]*?panel\.screenH[\s\S]*?Math\.min\(desired, available/);
  assert.match(qml, /id: calendarScroll[\s\S]*?contentHeight: calendarColumn\.implicitHeight[\s\S]*?interactive: contentHeight > height/);
  assert.match(qml, /id: zoneList[\s\S]*?height: visible \? Math\.min\(Style\.space\(180\), contentHeight\)/);
});

test("short-lived helper processes preserve lines and release their QML objects", () => {
  for (const file of ["Panel.qml", "BarWidget.qml"]) {
    const qml = fs.readFileSync(path.join(root, file), "utf8");
    assert.match(qml, /SplitParser[^\n]*onRead[^\n]*collected \+= d \+ /, file);
    assert.match(qml, /onExited: function\(\)\{ try \{ if \(this\.cb\) this\.cb\(collected\) \} finally \{ this\.destroy\(\) \} \}/, file);
  }
});
