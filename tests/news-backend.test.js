const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { spawnSync } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..");
const backend = path.join(repoRoot, "plugins", "news", "backend");
const rss = path.join(__dirname, "news-fixtures", "rss.xml");
const atom = path.join(__dirname, "news-fixtures", "atom.xml");

function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "supernotch-news-"));
  return { dir, home: path.join(dir, "home") };
}

function run(fx, args, options = {}) {
  const result = spawnSync(backend, args, {
    env: { ...process.env, HOME: fx.home, NEWS_ALLOW_FIXTURES: "1" },
    encoding: "utf8",
    input: options.input,
  });
  return result;
}

function jsonRun(fx, args) {
  const result = run(fx, args);
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

test("RSS parser extracts safe article fields and full content", () => {
  const fx = fixture();
  const articles = jsonRun(fx, ["parse-file", rss, "rss", "RSS Test", "https://example.test/rss"]);
  assert.equal(articles.length, 2);
  assert.deepEqual(
    Object.keys(articles[0]).sort(),
    ["content", "date", "id", "link", "sourceId", "sourceName", "summary", "title"].sort(),
  );
  assert.equal(articles[0].title, "Primera noticia");
  assert.equal(articles[0].summary, "Resumen RSS.");
  assert.equal(articles[0].content, "Contenido completo RSS.");
  assert.equal(articles[0].date, "2026-09-04T12:30:00+00:00");
});

test("Atom parser follows alternate links and extracts summary", () => {
  const fx = fixture();
  const articles = jsonRun(fx, ["parse-file", atom, "atom", "Atom Test", "https://example.test/atom"]);
  assert.equal(articles.length, 2);
  assert.equal(articles[0].link, "https://example.test/articles/shared?utm_medium=atom");
  assert.equal(articles[0].summary, "Atom summary");
  assert.equal(articles[1].date, "2026-09-04T10:00:00+00:00");
});

test("combined cache deduplicates tracking variants and preserves newest article", () => {
  const fx = fixture();
  const first = jsonRun(fx, ["add-source", "https://example.test/rss", "RSS Test"]);
  const second = jsonRun(fx, ["add-source", "https://example.test/atom", "Atom Test"]);
  jsonRun(fx, ["import-file", first.id, rss]);
  jsonRun(fx, ["import-file", second.id, atom]);
  const articles = jsonRun(fx, ["articles"]);
  assert.equal(articles.length, 3);
  assert.equal(articles[0].title, "Shared from Atom");
  assert.equal(articles.filter((item) => item.link.includes("/shared?")).length, 1);
});

test("read state can be toggled and survives another backend process", () => {
  const fx = fixture();
  const source = jsonRun(fx, ["add-source", "https://example.test/rss", "RSS Test"]);
  jsonRun(fx, ["import-file", source.id, rss]);
  let articles = jsonRun(fx, ["articles"]);
  const id = articles[0].id;
  jsonRun(fx, ["mark", id, "read"]);
  articles = jsonRun(fx, ["articles"]);
  assert.equal(articles.find((item) => item.id === id).unread, false);
  jsonRun(fx, ["mark", id, "unread"]);
  articles = jsonRun(fx, ["articles"]);
  assert.equal(articles.find((item) => item.id === id).unread, true);
});

test("failed refresh keeps cached fixture articles for offline reading", () => {
  const fx = fixture();
  for (const source of jsonRun(fx, ["sources"]).filter((item) => item.builtin)) {
    jsonRun(fx, ["toggle-source", source.id]);
  }
  const source = jsonRun(fx, ["add-source", "http://127.0.0.1:1/rss.xml", "Offline Test"]);
  jsonRun(fx, ["import-file", source.id, rss]);
  const result = jsonRun(fx, ["refresh"]);
  assert.equal(result.offline, true);
  assert.equal(result.cached, true);
  assert.equal(result.articles.length, 2);
  assert.ok(result.errors[source.id]);
});

test("user sources reorder, toggle, and remove without changing built-ins", () => {
  const fx = fixture();
  const a = jsonRun(fx, ["add-source", "https://one.example/feed", "One"]);
  const b = jsonRun(fx, ["add-source", "https://two.example/feed", "Two"]);
  let sources = jsonRun(fx, ["sources"]);
  const builtinCount = sources.filter((source) => source.builtin).length;
  assert.ok(builtinCount >= 4);
  assert.deepEqual(sources.slice(-2).map((source) => source.id), [a.id, b.id]);
  jsonRun(fx, ["move-source", b.id, "-1"]);
  sources = jsonRun(fx, ["sources"]);
  assert.deepEqual(sources.slice(-2).map((source) => source.id), [b.id, a.id]);
  jsonRun(fx, ["toggle-source", b.id]);
  assert.equal(jsonRun(fx, ["sources"]).find((source) => source.id === b.id).enabled, false);
  jsonRun(fx, ["remove-source", a.id]);
  assert.equal(jsonRun(fx, ["sources"]).some((source) => source.id === a.id), false);
  assert.notEqual(run(fx, ["remove-source", "bbc-mundo"]).status, 0);
});

test("source and article URL validation rejects unsafe schemes and credentials", () => {
  const fx = fixture();
  for (const url of ["file:///etc/passwd", "javascript:alert(1)", "https://user:pass@example.test/feed", "//example.test/feed", "not-a-url"]) {
    assert.notEqual(run(fx, ["add-source", url, "Bad"]).status, 0, url);
  }
  assert.equal(run(fx, ["validate-url", "https://example.test/article?q=ok"]).status, 0);
  assert.notEqual(run(fx, ["validate-url", "file:///tmp/article"]).status, 0);
});

test("XML parser rejects declarations and oversized fixture input", () => {
  const fx = fixture();
  const hostile = path.join(fx.dir, "hostile.xml");
  fs.writeFileSync(hostile, '<!DOCTYPE rss [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><rss><channel><item><title>&xxe;</title></item></channel></rss>');
  assert.notEqual(run(fx, ["parse-file", hostile, "bad", "Bad", "https://example.test/bad"]).status, 0);
  const huge = path.join(fx.dir, "huge.xml");
  fs.writeFileSync(huge, Buffer.alloc(2 * 1024 * 1024 + 1, "x"));
  assert.notEqual(run(fx, ["parse-file", huge, "bad", "Bad", "https://example.test/bad"]).status, 0);
});
