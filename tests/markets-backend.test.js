const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { spawnSync } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..");
const backend = path.join(repoRoot, "plugins", "markets", "backend");

function sandbox(extraEnv = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "supernotch-markets-"));
  return { home, env: { ...process.env, HOME: home, MARKETS_OFFLINE: "1", ...extraEnv } };
}

function run(box, args, expectedStatus = 0) {
  const result = spawnSync(backend, args, { env: box.env, encoding: "utf8" });
  const diagnostic = result.error ? result.error.message : (result.stderr || result.stdout || "unexpected exit");
  assert.equal(result.status, expectedStatus, diagnostic);
  return result.stdout.trim() ? JSON.parse(result.stdout) : null;
}

test("watchlist additions persist under the SuperNotch state directory", () => {
  const box = sandbox();
  run(box, ["add-symbol", " aapl "]);
  run(box, ["add-symbol", "MSFT"]);
  run(box, ["add-symbol", "AAPL"]);

  const state = run(box, ["state"]);
  assert.deepEqual(state.watchlist, ["AAPL", "MSFT"]);
  assert.deepEqual(state.holdings, {});

  const saved = JSON.parse(fs.readFileSync(path.join(box.home, ".local", "state", "omarchy-supernotch", "markets.json"), "utf8"));
  assert.deepEqual(saved.watchlist, ["AAPL", "MSFT"]);
});

test("symbols are validated before persistence", () => {
  const box = sandbox();
  const result = spawnSync(backend, ["add-symbol", "../bad"], { env: box.env, encoding: "utf8" });
  const diagnostic = result.error ? result.error.message : (result.stderr || "");
  assert.notEqual(result.status, 0);
  assert.match(diagnostic, /invalid symbol|ENOENT/i);
  assert.equal(fs.existsSync(path.join(box.home, ".local", "state", "omarchy-supernotch", "markets.json")), false);
});

test("watchlist reordering is persistent and bounded", () => {
  const box = sandbox();
  for (const ticker of ["AAPL", "MSFT", "NVDA"]) run(box, ["add-symbol", ticker]);
  assert.deepEqual(run(box, ["reorder", "NVDA", "-1"]).watchlist, ["AAPL", "NVDA", "MSFT"]);
  assert.deepEqual(run(box, ["reorder", "AAPL", "-1"]).watchlist, ["AAPL", "NVDA", "MSFT"]);
  assert.deepEqual(run(box, ["state"]).watchlist, ["AAPL", "NVDA", "MSFT"]);
});

test("multiple lots persist and expose cost basis only when complete", () => {
  const box = sandbox();
  run(box, ["add-symbol", "AAPL"]);
  let state = run(box, ["add-lot", "AAPL", "2", "2025-01-02", "100.50"]);
  const firstId = state.holdings.AAPL[0].id;
  state = run(box, ["add-lot", "AAPL", "1.5", "", ""]);
  const secondId = state.holdings.AAPL[1].id;
  assert.equal(state.holdings.AAPL.length, 2);

  let summary = run(box, ["summary", "AAPL", "120"]);
  assert.equal(summary.quantity, 3.5);
  assert.equal(summary.marketValue, 420);
  assert.equal(summary.costBasis, null);
  assert.equal(summary.gain, null);

  state = run(box, ["edit-lot", "AAPL", secondId, "1.5", "2025-02-03", "110"]);
  assert.equal(state.holdings.AAPL[1].date, "2025-02-03");
  summary = run(box, ["summary", "AAPL", "120"]);
  assert.equal(summary.costBasis, 366);
  assert.equal(summary.gain, 54);
  assert.equal(summary.gainPct, 14.7541);

  state = run(box, ["remove-lot", "AAPL", firstId]);
  assert.deepEqual(state.holdings.AAPL.map((lot) => lot.id), [secondId]);
});

test("removing a symbol with holdings requires explicit confirmation", () => {
  const box = sandbox();
  run(box, ["add-symbol", "AAPL"]);
  run(box, ["add-lot", "AAPL", "1", "", "100"]);
  const refused = spawnSync(backend, ["remove-symbol", "AAPL"], { env: box.env, encoding: "utf8" });
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /confirmation required/i);
  assert.deepEqual(run(box, ["remove-symbol", "AAPL", "confirm"]).watchlist, []);
  assert.deepEqual(run(box, ["state"]).holdings, {});
});

test("Yahoo chart fixtures parse quote metadata and non-null chart points", () => {
  const box = sandbox();
  const quoteFile = path.join(repoRoot, "tests", "markets-AAPL-5d.json");
  const chartFile = path.join(repoRoot, "tests", "markets-AAPL-1mo.json");
  assert.deepEqual(run(box, ["parse-quote", quoteFile]), {
    symbol: "AAPL", currency: "USD", price: 189.25, previousClose: 187.5,
    dayChange: 1.75, dayChangePct: 0.9333, marketTime: 1757000000,
  });
  assert.deepEqual(run(box, ["parse-chart", chartFile]).points, [
    { time: 1754000000, value: 181.5 },
    { time: 1755000000, value: 184 },
    { time: 1757000000, value: 189.25 },
  ]);
});

test("asset search finds symbols by company name without adding them", () => {
  const fixture = path.join(repoRoot, "tests", "markets-search-apple.json");
  const box = sandbox({ MARKETS_SEARCH_FIXTURE: fixture });
  const results = run(box, ["search", "apple"]);
  assert.deepEqual(results, [
    { symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", type: "Equity" },
    { symbol: "APLE", name: "Apple Hospitality REIT, Inc.", exchange: "NYSE", type: "Equity" },
  ]);
  assert.deepEqual(run(box, ["state"]).watchlist, []);
});

test("offline asset search fails cleanly without a traceback", () => {
  const box = sandbox();
  const result = spawnSync(backend, ["search", "Apple"], { env: box.env, encoding: "utf8" });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /offline fixture mode/i);
  assert.doesNotMatch(result.stderr, /Traceback/);
});

test("refresh uses fixtures, computes portfolio values, and falls back to stale cache", () => {
  const fixtureDir = fs.mkdtempSync(path.join(os.tmpdir(), "markets-fixtures-"));
  fs.copyFileSync(path.join(repoRoot, "tests", "markets-AAPL-5d.json"), path.join(fixtureDir, "markets-AAPL-5d.json"));
  const box = sandbox({ MARKETS_FIXTURE_DIR: fixtureDir });
  run(box, ["add-symbol", "AAPL"]);
  run(box, ["add-lot", "AAPL", "2", "", "150"]);
  let result = run(box, ["refresh", "--force"]);
  assert.equal(result.assets[0].price, 189.25);
  assert.deepEqual(result.assets[0].sparkline, [188, 189.25]);
  assert.equal(result.assets[0].gain, 78.5);
  assert.equal(result.assets[0].gainPct, 26.1667);
  assert.equal(result.assets[0].stale, false);

  fs.rmSync(path.join(fixtureDir, "markets-AAPL-5d.json"));
  result = run(box, ["refresh", "--force"]);
  assert.equal(result.assets[0].price, 189.25);
  assert.equal(result.assets[0].stale, true);
  assert.match(result.assets[0].warning, /cached/i);
});

test("detail chart supports named ranges without a network dependency", () => {
  const fixtureDir = fs.mkdtempSync(path.join(os.tmpdir(), "markets-chart-fixtures-"));
  fs.copyFileSync(path.join(repoRoot, "tests", "markets-AAPL-1mo.json"), path.join(fixtureDir, "markets-AAPL-1mo.json"));
  const box = sandbox({ MARKETS_FIXTURE_DIR: fixtureDir });
  const chart = run(box, ["chart", "AAPL", "1M", "--force"]);
  assert.equal(chart.range, "1M");
  assert.equal(chart.stale, false);
  assert.equal(chart.points.length, 3);
});

test("localized decimal inputs work and mixed instrument currencies stay separate", () => {
  const fixtureDir = fs.mkdtempSync(path.join(os.tmpdir(), "markets-currency-fixtures-"));
  const usd = fs.readFileSync(path.join(repoRoot, "tests", "markets-AAPL-5d.json"), "utf8");
  fs.writeFileSync(path.join(fixtureDir, "markets-AAPL-5d.json"), usd);
  fs.writeFileSync(path.join(fixtureDir, "markets-SAP.DE-5d.json"), usd.replaceAll("AAPL", "SAP.DE").replaceAll("USD", "EUR"));
  const box = sandbox({ MARKETS_FIXTURE_DIR: fixtureDir });
  run(box, ["add-symbol", "AAPL"]);
  let state = run(box, ["add-lot", "SAP.DE", "1,5", "", "100,25"]);
  assert.equal(state.holdings["SAP.DE"][0].quantity, 1.5);
  assert.equal(state.holdings["SAP.DE"][0].price, 100.25);

  const result = run(box, ["refresh", "--force"]);
  assert.deepEqual(result.assets.map((asset) => asset.currency), ["USD", "EUR"]);
  assert.equal(Object.hasOwn(result, "portfolioTotal"), false);
});

test("portfolio rejects finite inputs that would produce Infinity or NaN", () => {
  const box = sandbox();
  run(box, ["add-symbol", "AAPL"]);
  for (const value of ["1e308", "Infinity", "NaN"]) {
    const result = spawnSync(backend, ["add-lot", "AAPL", value, "", "100"], { encoding: "utf8", env: box.env });
    assert.notEqual(result.status, 0, value);
  }
  const raw = spawnSync(backend, ["summary", "AAPL", "1e308"], { encoding: "utf8", env: box.env });
  assert.notEqual(raw.status, 0);
  assert.doesNotMatch(raw.stdout, /Infinity|NaN/);
});
