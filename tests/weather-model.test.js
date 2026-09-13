const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const repoRoot = path.resolve(__dirname, "..");

function loadModel() {
  const source = fs.readFileSync(path.join(repoRoot, "plugins/weather/Model.js"), "utf8");
  const context = { module: { exports: {} }, Date };
  vm.createContext(context);
  vm.runInContext(source, context, { filename: "Model.js" });
  return context.module.exports;
}

test("per-city runtime updates preserve cached weather for every other city", () => {
  const model = loadModel();
  const cities = [
    { id: "scl", name: "Santiago", weather: { temp: "18" }, loading: false, error: "" },
    { id: "pmc", name: "Puerto Montt", weather: { temp: "9" }, loading: false, error: "old" },
  ];

  const loading = model.updateCityRuntime(cities, "pmc", { loading: true, error: "" });
  assert.equal(loading[0], cities[0]);
  assert.equal(loading[1].weather.temp, "9");
  assert.equal(loading[1].loading, true);
  assert.equal(loading[1].error, "");
  assert.equal(cities[1].loading, false);
});

test("response tokens reject out-of-order forecast and autocomplete callbacks", () => {
  const model = loadModel();
  const tokens = { search: 4, scl: 7 };
  assert.equal(model.responseIsCurrent(tokens, "search", 3), false);
  assert.equal(model.responseIsCurrent(tokens, "search", 4), true);
  assert.equal(model.responseIsCurrent(tokens, "scl", 6), false);
  assert.equal(model.responseIsCurrent(tokens, "scl", 7), true);
});

test("Open-Meteo report is normalized with the system weather model", () => {
  const model = loadModel();
  const report = JSON.parse(fs.readFileSync(path.join(repoRoot, "tests/weather-forecast.json"), "utf8"));
  const weather = model.cityWeather(report, "2026-09-04");
  assert.deepEqual(JSON.parse(JSON.stringify(weather)), {
    temp: "18", feels: "17", humidity: "61", wind: "12", code: 2, isDay: 1,
    icon: "", maxC: "21", minC: "9",
    forecast: [
      { date: "2026-09-05", maxC: "20", minC: "9", icon: "" },
      { date: "2026-09-06", maxC: "20", minC: "8", icon: "" },
      { date: "2026-09-07", maxC: "22", minC: "10", icon: "" },
    ],
  });
});
