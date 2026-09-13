const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { spawn, spawnSync } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..");
const backend = path.join(repoRoot, "plugins", "weather", "backend");

function sandbox() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "supernotch-weather-"));
  const bin = path.join(home, "bin");
  fs.mkdirSync(bin);
  const locationCommand = path.join(bin, "omarchy-weather-location");
  fs.writeFileSync(locationCommand, `#!/bin/bash
set -u
[[ \${WEATHER_LOCATION_FAIL:-0} == 1 ]] && exit 9
file="$HOME/.local/state/omarchy/settings/weather.json"
mkdir -p "$(dirname "$file")"
name=$2; coords=$3
python3 - "$file" "$name" "\${coords%,*}" "\${coords#*,}" <<'PY'
import json, os, sys
path, name, latitude, longitude = sys.argv[1:]
temporary = path + ".tmp"
with open(temporary, "w", encoding="utf-8") as stream:
    json.dump({"name": name, "latitude": float(latitude), "longitude": float(longitude)}, stream)
os.replace(temporary, path)
PY
`, { mode: 0o755 });
  return { home, env: { ...process.env, HOME: home, PATH: `${bin}:${process.env.PATH}`, WEATHER_LOCATION_COMMAND: locationCommand, WEATHER_LOCATION_FAIL: "0", WEATHER_OFFLINE: "1" } };
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value));
}

function run(box, args, expectedStatus = 0) {
  const result = spawnSync(backend, args, { env: box.env, encoding: "utf8" });
  const diagnostic = result.error ? result.error.message : (result.stderr || result.stdout || "unexpected exit");
  assert.equal(result.status, expectedStatus, diagnostic);
  return result.stdout.trim() ? JSON.parse(result.stdout) : null;
}

function runAsync(box, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(backend, args, { env: box.env });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", chunk => { stdout += chunk; });
    child.stderr.on("data", chunk => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", status => status === 0 ? resolve(JSON.parse(stdout)) : reject(new Error(stderr || `exit ${status}`)));
  });
}

function candidate(index) {
  return { name: `City ${index}`, region: `Region ${index}`, country: "Chile", countryCode: "CL",
    latitude: -40 + index, longitude: -70, displayName: `City ${index}, Region ${index}, Chile` };
}

test("first state read migrates the current Omarchy weather location into its own sidecar", () => {
  const box = sandbox();
  const omarchyState = path.join(box.home, ".local", "state", "omarchy", "settings", "weather.json");
  writeJson(omarchyState, { name: "Santiago", latitude: -33.4489, longitude: -70.6693 });
  const state = run(box, ["state"]);
  assert.equal(state.version, 1);
  assert.equal(state.cities.length, 1);
  assert.equal(state.activeId, state.cities[0].id);
  assert.deepEqual({ name: state.cities[0].name, latitude: state.cities[0].latitude, longitude: state.cities[0].longitude },
    { name: "Santiago", latitude: -33.4489, longitude: -70.6693 });
  const sidecar = path.join(box.home, ".local", "state", "omarchy-supernotch", "weather.json");
  assert.deepEqual(JSON.parse(fs.readFileSync(sidecar, "utf8")), state);
  assert.deepEqual(JSON.parse(fs.readFileSync(omarchyState, "utf8")), { name: "Santiago", latitude: -33.4489, longitude: -70.6693 });
});

test("city search requires two characters and returns canonical place identity", () => {
  const fixture = path.join(repoRoot, "tests", "weather-search-santiago.json");
  const box = sandbox();
  box.env.WEATHER_SEARCH_FIXTURE = fixture;
  const tooShort = spawnSync(backend, ["search", "S"], { env: box.env, encoding: "utf8" });
  assert.notEqual(tooShort.status, 0);
  assert.match(tooShort.stderr, /at least two/i);
  const results = run(box, ["search", "Santiago"]);
  assert.deepEqual(results[0], { name: "Santiago", region: "Santiago Metropolitan", country: "Chile", countryCode: "CL",
    latitude: -33.45694, longitude: -70.64827, displayName: "Santiago, Santiago Metropolitan, Chile" });
  assert.equal(results.length, 2);
});

test("city mutations reject boolean coordinates before persistence", () => {
  const box = sandbox();
  const invalid = JSON.stringify({ name: "Bool City", latitude: true, longitude: 2 });
  const result = spawnSync(backend, ["add-city", invalid], { env: box.env, encoding: "utf8" });
  assert.notEqual(result.status, 0);
  const stateFile = path.join(box.home, ".local", "state", "omarchy-supernotch", "weather.json");
  const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
  assert.deepEqual(state.cities, []);
});

test("cities persist canonical metadata, cap at eight, activate, reorder and remove", () => {
  const box = sandbox();
  let state;
  for (let index = 0; index < 8; index++) state = run(box, ["add-city", JSON.stringify(candidate(index))]);
  assert.equal(state.cities.length, 8);
  assert.equal(state.cities[7].displayName, "City 7, Region 7, Chile");
  const overflow = spawnSync(backend, ["add-city", JSON.stringify(candidate(9))], { env: box.env, encoding: "utf8" });
  assert.notEqual(overflow.status, 0);
  assert.match(overflow.stderr, /eight cities/i);
  const lastId = state.cities[7].id;
  state = run(box, ["activate", lastId]);
  assert.equal(state.activeId, lastId);
  state = run(box, ["reorder", lastId, "-1"]);
  assert.equal(state.cities[6].id, lastId);
  state = run(box, ["remove", lastId]);
  assert.equal(state.cities.length, 7);
  assert.notEqual(state.activeId, lastId);
  assert.equal(run(box, ["state"]).cities.length, 7);
});

test("coordinate normalization blocks duplicates and requires confirmation for nearby places", () => {
  const box = sandbox();
  const first = { name: "Santiago", region: "RM", country: "Chile", countryCode: "CL", latitude: -33.45, longitude: -70.66 };
  const exact = { ...first, name: "SANTIAGO", latitude: -33.4500001, longitude: -70.6600001 };
  const nearby = { ...first, name: "Providencia", latitude: -33.43, longitude: -70.61 };
  run(box, ["add-city", JSON.stringify(first)]);
  const duplicate = run(box, ["add-city", JSON.stringify(exact)]);
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.requiresConfirmation, false);
  assert.equal(run(box, ["state"]).cities.length, 1);
  const warning = run(box, ["add-city", JSON.stringify(nearby)]);
  assert.equal(warning.duplicate, false);
  assert.equal(warning.requiresConfirmation, true);
  assert.match(warning.message, /nearby/i);
  assert.equal(run(box, ["state"]).cities.length, 1);
  assert.equal(run(box, ["add-city", JSON.stringify(nearby), "confirm"]).cities.length, 2);
});

test("editing replaces a city in place instead of silently adding another", () => {
  const box = sandbox();
  let state = run(box, ["add-city", JSON.stringify(candidate(0))]);
  state = run(box, ["add-city", JSON.stringify(candidate(2))]);
  const originalId = state.cities[0].id;
  const replacement = { ...candidate(5), name: "Canonical replacement" };
  state = run(box, ["replace-city", originalId, JSON.stringify(replacement)]);
  assert.equal(state.cities.length, 2);
  assert.equal(state.cities[0].id, originalId);
  assert.equal(state.cities[0].name, "Canonical replacement");
  assert.equal(state.cities[1].name, "City 2");
});

test("forecast returns the system-compatible Open-Meteo report for exact coordinates", () => {
  const box = sandbox();
  box.env.WEATHER_FORECAST_FIXTURE = path.join(repoRoot, "tests", "weather-forecast.json");
  const report = run(box, ["forecast", "-33.45", "-70.65"]);
  assert.equal(report.current.temperature_2m, 18.4);
  assert.equal(report.current.weather_code, 2);
  assert.equal(report.daily.time.length, 4);
  for (const args of [["forecast", "nan", "-70"], ["forecast", "91", "0"], ["forecast", "0", "181"]]) {
    const invalid = spawnSync(backend, args, { env: box.env, encoding: "utf8" });
    assert.notEqual(invalid.status, 0);
    assert.match(invalid.stderr, /coordinates/i);
  }
});

test("activation syncs the exact Omarchy weather schema and rolls back on sync failure", () => {
  const box = sandbox();
  let state = run(box, ["add-city", JSON.stringify({ ...candidate(0), name: "Santiago" })]);
  state = run(box, ["add-city", JSON.stringify({ ...candidate(2), name: "Valparaíso", latitude: -33.0472, longitude: -71.6127 })]);
  const firstId = state.cities[0].id;
  const secondId = state.cities[1].id;
  state = run(box, ["activate", secondId]);
  const omarchyFile = path.join(box.home, ".local", "state", "omarchy", "settings", "weather.json");
  const synced = JSON.parse(fs.readFileSync(omarchyFile, "utf8"));
  assert.deepEqual(Object.keys(synced).sort(), ["latitude", "longitude", "name"]);
  assert.deepEqual(synced, { name: "Valparaíso", latitude: -33.0472, longitude: -71.6127 });
  const failed = spawnSync(backend, ["activate", firstId], { env: { ...box.env, WEATHER_LOCATION_FAIL: "1" }, encoding: "utf8" });
  assert.notEqual(failed.status, 0);
  assert.equal(run(box, ["state"]).activeId, secondId);
  assert.deepEqual(JSON.parse(fs.readFileSync(omarchyFile, "utf8")), synced);
});

test("geocoding cache normalizes queries, survives offline errors, and stays bounded", () => {
  const fixture = path.join(repoRoot, "tests", "weather-search-santiago.json");
  const box = sandbox();
  box.env.WEATHER_SEARCH_FIXTURE = fixture;
  const online = run(box, ["search", "  Santiago  "]);
  delete box.env.WEATHER_SEARCH_FIXTURE;
  assert.deepEqual(run(box, ["search", "SANTIAGO"]), online);
  box.env.WEATHER_SEARCH_FIXTURE = fixture;
  for (let index = 0; index < 40; index++) run(box, ["search", `place ${index}`]);
  const cacheFile = path.join(box.home, ".local", "state", "omarchy-supernotch", "weather-geocode-cache.json");
  const beforeError = fs.readFileSync(cacheFile, "utf8");
  assert.ok(Object.keys(JSON.parse(beforeError).entries).length <= 32);
  delete box.env.WEATHER_SEARCH_FIXTURE;
  const missing = spawnSync(backend, ["search", "never cached"], { env: box.env, encoding: "utf8" });
  assert.notEqual(missing.status, 0);
  assert.equal(fs.readFileSync(cacheFile, "utf8"), beforeError);
});

test("concurrent city mutations serialize without losing updates", async () => {
  for (let trial = 0; trial < 10; trial++) {
    const box = sandbox();
    await Promise.all([
      runAsync(box, ["add-city", JSON.stringify(candidate(0))]),
      runAsync(box, ["add-city", JSON.stringify(candidate(2))]),
    ]);
    assert.equal(run(box, ["state"]).cities.length, 2, `trial ${trial}`);
  }
});

test("corrupt city state is never replaced by a later mutation", () => {
  const validCity = { id: "a", name: "A", region: "", country: "", countryCode: "", latitude: 1, longitude: 2, displayName: "A" };
  const corruptStates = [
    "{not-json\n",
    "[]\n",
    JSON.stringify({ version: 1, activeId: "a", cities: [{ id: "a", name: "A" }] }),
    JSON.stringify({ version: 1, activeId: "a", cities: [{ ...validCity, latitude: true }] }),
    JSON.stringify({ version: 1, activeId: "missing", cities: [validCity] }),
  ];
  for (const corrupt of corruptStates) {
    const box = sandbox();
    const stateFile = path.join(box.home, ".local", "state", "omarchy-supernotch", "weather.json");
    fs.mkdirSync(path.dirname(stateFile), { recursive: true });
    fs.writeFileSync(stateFile, corrupt);
    const result = spawnSync(backend, ["add-city", JSON.stringify(candidate(0))], { env: box.env, encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /invalid weather state/i);
    assert.doesNotMatch(result.stderr, /Traceback/);
    assert.equal(fs.readFileSync(stateFile, "utf8"), corrupt);
  }
});
