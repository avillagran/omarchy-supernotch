const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { spawnSync } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..");

function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "supernotch-plugin-exec-"));
  const binDir = path.join(dir, "bin");
  const pluginDir = path.join(dir, "plugins", "demo");
  fs.mkdirSync(binDir, { recursive: true });
  fs.mkdirSync(pluginDir, { recursive: true });
  fs.copyFileSync(path.join(repoRoot, "bin", "omarchy-supernotch"), path.join(binDir, "omarchy-supernotch"));
  fs.chmodSync(path.join(binDir, "omarchy-supernotch"), 0o755);
  fs.writeFileSync(path.join(pluginDir, "backend"), "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\"\n", { mode: 0o755 });
  return dir;
}

function run(root, args) {
  return spawnSync(path.join(root, "bin", "omarchy-supernotch"), args, {
    cwd: root,
    env: { ...process.env, HOME: path.join(root, "home"), XDG_RUNTIME_DIR: path.join(root, "run") },
    encoding: "utf8",
  });
}

test("plugin-exec delegates arguments to a plugin-local executable", () => {
  const root = fixture();
  const result = run(root, ["plugin-exec", "demo", "status", "one value"]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "status one value\n");
});

test("plugin-exec rejects traversal and missing backends", () => {
  const root = fixture();
  assert.notEqual(run(root, ["plugin-exec", "../demo", "status"]).status, 0);
  assert.notEqual(run(root, ["plugin-exec", "missing", "status"]).status, 0);
});
