const assert = require("node:assert/strict");
const { execFileSync, spawnSync } = require("node:child_process");
const { createHash } = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const backend = path.resolve(__dirname, "../plugins/weather/rust/target/release/supernotch-weather");
const variables = ["precipitation", "cloud_cover", "temperature_2m", "wind_speed_10m", "wind_direction_10m", "relative_humidity_2m"];

function renderFixture(zoom = 1, hours = 10, model = "ecmwf_ifs", direction = 270) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "supernotch-map-"));
  const state = path.join(home, ".local/state/omarchy-supernotch");
  fs.mkdirSync(state, { recursive: true });
  const times = Array.from({ length: hours }, (_, hour) =>
    `2026-09-24T${String(3 + (hours === 4 ? hour * 3 : hour)).padStart(2, "0")}:00`);
  const values = {};
  for (const variable of variables) {
    values[variable] = variable === "wind_direction_10m" ? times.map(() => [
      [direction, direction], [direction, direction],
    ]) : times.map((_, index) => [
      [variable === "precipitation" ? index + 0.2 : 30 + index * 10, 10 + index],
      [20 + index, 40 + index],
    ]);
  }
  const cache = {
    fetchedAt: Math.floor(Date.now() / 1000),
    model, lats: [-41.0, -44.0], lons: [-76.0, -71.0], times, values,
  };
  fs.writeFileSync(path.join(state, `ifs-grid--42.4828_-73.7672_z${zoom}.json`), JSON.stringify(cache));
  return { home, state, times };
}

test("wind and rainy-region airflow symbols use the direction field only above eight GiB", (t) => {
  const west = renderFixture();
  const east = renderFixture(1, 10, "ecmwf_ifs", 90);
  t.after(() => {
    fs.rmSync(west.home, { recursive: true, force: true });
    fs.rmSync(east.home, { recursive: true, force: true });
  });
  const render = (fixture, layer) => JSON.parse(execFileSync(backend,
    ["chart", "-42.4828", "-73.7672", layer, "1"], {
      env: { ...process.env, HOME: fixture.home, WEATHER_OFFLINE: "1" }, encoding: "utf8", timeout: 15_000,
    }));
  const allowed = Number(fs.readFileSync("/proc/meminfo", "utf8").match(/^MemTotal:\s*(\d+) kB/m)?.[1] || 0) > 8 * 1024 * 1024;
  const digest = frame => createHash("sha256").update(fs.readFileSync(frame.path)).digest("hex");
  for (const layer of ["wind", "rain", "clouds"]) {
    const a = render(west, layer);
    const b = render(east, layer);
    assert.equal(a.flowMarkers, allowed && layer !== "clouds");
    assert.equal(b.flowMarkers, allowed && layer !== "clouds");
    if (allowed && layer !== "clouds") assert.notEqual(digest(a.frames[0]), digest(b.frames[0]), layer);
    else assert.equal(digest(a.frames[0]), digest(b.frames[0]), layer);
  }
});

test("an hourly forecast renders ten consecutive steps across the same nine-hour range", (t) => {
  const fixture = renderFixture(1, 10);
  t.after(() => fs.rmSync(fixture.home, { recursive: true, force: true }));
  const result = JSON.parse(execFileSync(backend, ["chart", "-42.4828", "-73.7672", "clouds", "1"], {
    env: { ...process.env, HOME: fixture.home, WEATHER_OFFLINE: "1" }, encoding: "utf8", timeout: 15_000,
  }));
  assert.equal(result.frames.length, 10);
  assert.deepEqual(result.frames.map(frame => frame.valid), fixture.times);
  assert.equal(result.frames[9].valid, "2026-09-24T12:00");
  assert.equal(result.model, "ecmwf_ifs");
});

test("a four-step cache does not masquerade as an hourly forecast after upgrading", (t) => {
  const fixture = renderFixture(1, 4);
  t.after(() => fs.rmSync(fixture.home, { recursive: true, force: true }));
  const env = { ...process.env, HOME: fixture.home, WEATHER_OFFLINE: "1" };
  const cached = spawnSync(backend, ["chart", "-42.4828", "-73.7672", "rain", "1"], { env, encoding: "utf8" });
  assert.equal(cached.status, 1);
  assert.match(cached.stderr, /no cached IFS map/);
  const live = spawnSync(backend, ["chart-live", "-42.4828", "-73.7672", "rain", "1"], { env, encoding: "utf8" });
  assert.equal(live.status, 1);
  assert.match(live.stderr, /offline and no cached IFS timeline/);
});

test("a ten-step cache from the coarser model is not mislabeled as hourly HRES", (t) => {
  const fixture = renderFixture(1, 10, "ecmwf_ifs025");
  t.after(() => fs.rmSync(fixture.home, { recursive: true, force: true }));
  const env = { ...process.env, HOME: fixture.home, WEATHER_OFFLINE: "1" };
  for (const command of ["chart", "chart-live"]) {
    const result = spawnSync(backend, [command, "-42.4828", "-73.7672", "wind", "1"], { env, encoding: "utf8" });
    assert.equal(result.status, 1, command);
  }
});

test("a cached IFS timeline renders distinct hourly forecast frames without network", (t) => {
  const fixture = renderFixture();
  t.after(() => fs.rmSync(fixture.home, { recursive: true, force: true }));
  const text = execFileSync(backend, ["chart", "-42.4828", "-73.7672", "rain", "1"], {
    env: { ...process.env, HOME: fixture.home, WEATHER_OFFLINE: "1" }, encoding: "utf8", timeout: 10_000,
  });
  const result = JSON.parse(text);
  assert.equal(result.zoom, 1);
  assert.equal(result.layer, "rain");
  assert.equal(result.frames.length, 10);
  assert.deepEqual(result.frames.map(frame => frame.valid), fixture.times);
  assert.equal(new Set(result.frames.map(frame => frame.path)).size, 10);
  assert.ok(result.labels.some(label => label.name === "Castro" && label.x > 0 && label.x < 1));
  assert.ok(result.scaleKm > 0 && result.scalePx > 0);
  for (const frame of result.frames) {
    const png = fs.readFileSync(frame.path);
    assert.equal(png.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
    assert.equal(png.readUInt32BE(16), 1024);
    assert.equal(png.readUInt32BE(20), 320);
  }
});

test("zoom changes the geographic window instead of stretching the same pixels", (t) => {
  const fixture = renderFixture();
  t.after(() => fs.rmSync(fixture.home, { recursive: true, force: true }));
  const cache = fs.readFileSync(path.join(fixture.state, "ifs-grid--42.4828_-73.7672_z1.json"));
  fs.writeFileSync(path.join(fixture.state, "ifs-grid--42.4828_-73.7672_z3.json"), cache);
  const run = zoom => JSON.parse(execFileSync(backend,
    ["chart", "-42.4828", "-73.7672", "temperature", String(zoom)], {
      env: { ...process.env, HOME: fixture.home, WEATHER_OFFLINE: "1" }, encoding: "utf8", timeout: 10_000,
    }));
  const regional = run(1);
  const close = run(3);
  assert.equal(close.zoom, 3);
  const digest = frame => createHash("sha256").update(fs.readFileSync(frame.path)).digest("hex");
  assert.notEqual(digest(regional.frames[0]), digest(close.frames[0]));
});

test("an actual cached IFS snapshot remains visible when the hourly service is unavailable", (t) => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "supernotch-map-snapshot-"));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const dir = path.join(home, ".local/state/omarchy-supernotch");
  fs.mkdirSync(dir, { recursive: true });
  const values = {};
  for (const name of ["precipitation", "cloud_cover", "temperature_2m", "wind_speed_10m", "relative_humidity_2m"])
    values[name] = [[1, 2], [3, 4]];
  fs.writeFileSync(path.join(dir, "ifs-grid--42_-74.json"), JSON.stringify({
    fetchedAt: Math.floor(Date.now() / 1000), runTime: "2026-09-24T00:00",
    lats: [-43, -42], lons: [-74, -73], values
  }));
  const result = JSON.parse(execFileSync(backend, ["chart", "-42.4828", "-73.7672", "rain", "3"],
    { env: { ...process.env, HOME: home, WEATHER_OFFLINE: "1" }, encoding: "utf8" }));
  assert.equal(result.frames.length, 1);
  assert.equal(result.snapshot, true);
  assert.equal(result.zoom, 3);
  assert.ok(fs.existsSync(result.frames[0].path));
});
