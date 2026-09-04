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
  const source = jsonRun(fx, ["add-source", "https://offline.invalid/rss.xml", "Offline Test"]);
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

test("Omarchy is the first built-in source after All", () => {
  const fx = fixture();
  const sources = jsonRun(fx, ["sources"]);
  assert.equal(sources[0].id, "omarchy");
  assert.equal(sources[0].name, "Omarchy");
  assert.equal(sources[0].url, "https://github.com/basecamp/omarchy/releases.atom");
  assert.equal(sources[0].builtin, true);
});

test("source and article URL validation rejects unsafe schemes, credentials and private targets", () => {
  const fx = fixture();
  for (const url of [
    "file:///etc/passwd",
    "javascript:alert(1)",
    "https://user:pass@example.test/feed",
    "//example.test/feed",
    "not-a-url",
    "http://127.0.0.1/feed",
    "http://[::1]/feed",
    "http://169.254.169.254/latest/meta-data",
    "http://10.0.0.1/feed",
    "http://192.168.1.1/feed",
    "http://localhost/feed",
    "http://localhost./feed",
  ]) {
    assert.notEqual(run(fx, ["add-source", url, "Bad"]).status, 0, url);
  }
  assert.equal(run(fx, ["validate-url", "https://example.com/article?q=ok"]).status, 0);
  assert.notEqual(run(fx, ["validate-url", "file:///tmp/article"]).status, 0);
  assert.notEqual(run(fx, ["validate-url", "http://localhost.localdomain/article"]).status, 0);
});

test("feed downloader pins validated addresses and resolves every redirect separately", () => {
  const source = fs.readFileSync(backend, "utf8");
  assert.match(source, /class PinnedHTTPConnection\(http\.client\.HTTPConnection\)/);
  assert.match(source, /class PinnedHTTPSConnection\(http\.client\.HTTPSConnection\)/);
  assert.match(source, /resolve_public_targets\(current_url\)/);
  assert.match(source, /urllib\.parse\.urljoin\(current_url,\s*location\)/);
  assert.match(source, /socket\.getaddrinfo/);
  assert.match(source, /not address\.is_global/);
  assert.doesNotMatch(source, /urllib\.request\.build_opener/);
});

test("download pins the validated address and cannot be DNS-rebound to localhost", () => {
  const script = String.raw`
import http.server, importlib.machinery, importlib.util, socket, sys, threading
loader = importlib.machinery.SourceFileLoader("news_backend", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
hits = 0
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global hits
        hits += 1
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"<rss><channel/></rss>")
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
real_getaddrinfo = socket.getaddrinfo
calls = 0
def rebinding(host, port, *args, **kwargs):
    global calls
    calls += 1
    address = "93.184.216.34" if calls == 1 else "127.0.0.1"
    return [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", (address, port))]
socket.getaddrinfo = rebinding
try:
    module.download(f"http://rebind.test:{server.server_port}/feed")
except Exception:
    pass
finally:
    socket.getaddrinfo = real_getaddrinfo
    server.shutdown()
print(f"hits={hits} dns_calls={calls}")
sys.exit(0 if hits == 0 else 1)
`;
  const result = spawnSync("python3", ["-c", script, backend], { encoding: "utf8" });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.match(result.stdout, /hits=0/);
});

test("open resolves a cached built-in article id and rejects custom-feed originals", () => {
  const fx = fixture();
  const trusted = path.join(fx.dir, "omarchy.xml");
  fs.writeFileSync(trusted, `<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><entry><id>release-1</id><title>Omarchy release</title><link rel="alternate" href="https://github.com/basecamp/omarchy/releases/tag/v1.0.0"/><updated>2026-09-04T10:00:00Z</updated></entry></feed>`);
  jsonRun(fx, ["import-file", "omarchy", trusted]);
  const trustedArticle = jsonRun(fx, ["articles"])[0];
  const trustedOpen = spawnSync(backend, ["open", trustedArticle.id], {
    encoding: "utf8",
    env: { ...process.env, HOME: fx.home, NEWS_ALLOW_FIXTURES: "1", NEWS_OPEN_DRY_RUN: "1" },
  });
  assert.equal(trustedOpen.status, 0, trustedOpen.stderr);
  assert.equal(JSON.parse(trustedOpen.stdout).url, "https://github.com/basecamp/omarchy/releases/tag/v1.0.0");

  const custom = jsonRun(fx, ["add-source", "https://example.test/rss", "Custom"]);
  jsonRun(fx, ["import-file", custom.id, rss]);
  const customArticle = jsonRun(fx, ["articles"]).find((article) => article.sourceId === custom.id);
  const customOpen = run(fx, ["open", customArticle.id]);
  assert.notEqual(customOpen.status, 0);
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
