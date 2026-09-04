const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { spawnSync } = require("node:child_process");

const backend = path.resolve(__dirname, "../plugins/monitor/backend");

function write(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}

function procStat(pid, name, utime, stime, starttime = 50) {
  return `${pid} (${name}) S 0 0 0 0 0 0 0 0 0 0 ${utime} ${stime} 0 0 20 0 1 0 ${starttime} 0 0\n`;
}

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "supernotch-monitor-"));
  const proc = path.join(root, "proc");
  const state = path.join(root, "state");
  fs.mkdirSync(state);
  write(path.join(proc, "stat"), "cpu 100 0 100 800 0 0 0 0 0 0\ncpu0 50 0 50 400\ncpu1 50 0 50 400\n");
  write(path.join(proc, "meminfo"), "MemTotal:       1000 kB\nMemAvailable:    400 kB\n");
  write(path.join(proc, "loadavg"), "0.25 0.50 0.75 1/20 99\n");
  write(path.join(proc, "uptime"), "90061.00 0.00\n");
  addProcess(proc, 1, "systemd", 4, 1, 100, "/sbin/init");
  addProcess(proc, 100, "worker alpha", 10, 10, 100, "/usr/bin/worker\0--serve");
  addProcess(proc, 200, "other", 5, 5, 50, "/usr/bin/other");
  addProcess(proc, 300, "bash", 1, 1, 20, "/bin/bash");
  addProcess(proc, 400, "helper-agent", 1, 1, 20, "/tmp/plugins/monitor/backend\0snapshot");
  return { root, proc, state };
}

function addProcess(proc, pid, name, utime, stime, rssKb, cmdline) {
  const dir = path.join(proc, String(pid));
  write(path.join(dir, "stat"), procStat(pid, name, utime, stime));
  write(path.join(dir, "status"), `Name:\t${name}\nState:\tS (sleeping)\nVmRSS:\t${rssKb} kB\nThreads:\t2\nUid:\t1000 1000 1000 1000\n`);
  write(path.join(dir, "cmdline"), cmdline);
}

function run(f, args, extraEnv = {}) {
  const result = spawnSync(backend, args, {
    encoding: "utf8",
    env: {
      ...process.env,
      LC_ALL: "C",
      MONITOR_PROC_ROOT: f.proc,
      MONITOR_STATE_DIR: f.state,
      MONITOR_KILL_DRY_RUN: "1",
      ...extraEnv,
    },
  });
  return result;
}

function json(result) {
  assert.equal(result.status, 0, result.stderr || result.error?.message || "backend failed");
  return JSON.parse(result.stdout);
}

test("snapshot parses memory, load, uptime and computes CPU deltas", () => {
  const f = fixture();
  json(run(f, ["snapshot", "cpu", ""]));
  write(path.join(f.proc, "stat"), "cpu 150 0 130 820 0 0 0 0 0 0\ncpu0 75 0 65 410\ncpu1 75 0 65 410\n");
  write(path.join(f.proc, "100/stat"), procStat(100, "worker alpha", 40, 20));

  const result = json(run(f, ["snapshot", "cpu", ""]));
  assert.equal(result.cpuPercent, 80);
  assert.equal(result.memory.totalKb, 1000);
  assert.equal(result.memory.usedKb, 600);
  assert.equal(result.memory.percent, 60);
  assert.deepEqual(result.load, [0.25, 0.5, 0.75]);
  assert.equal(result.uptimeSeconds, 90061);
  assert.equal(result.processes.find(p => p.pid === 100).cpu, 80);
});

test("snapshot emits JSON decimal points under an es_CL caller locale", () => {
  const f = fixture();
  const result = run(f, ["snapshot", "cpu", ""], { LANG: "es_CL.UTF-8", LC_ALL: "es_CL.UTF-8" });
  assert.match(fs.readFileSync(backend, "utf8"), /export LC_ALL=C LANG=C/);
  assert.doesNotThrow(() => JSON.parse(result.stdout));
  assert.doesNotMatch(result.stderr, /warning: regexp escape sequence/);
});

test("snapshot filters names and sorts process rows without losing fields", () => {
  const f = fixture();
  const result = json(run(f, ["snapshot", "ram", "worker"]));
  assert.equal(result.processes.length, 1);
  assert.deepEqual(result.processes[0], { pid: 100, name: "worker alpha", cpu: 0, ram: 10, rssKb: 100 });

  const byPid = json(run(f, ["snapshot", "pid", ""])).processes.map(p => p.pid);
  assert.deepEqual(byPid, [1, 100, 200, 300, 400]);
});

test("detail reports command, state, memory, threads and start time", () => {
  const f = fixture();
  const result = json(run(f, ["detail", "100"]));
  assert.equal(result.pid, 100);
  assert.equal(result.name, "worker alpha");
  assert.equal(result.command, "/usr/bin/worker --serve");
  assert.equal(result.state, "S (sleeping)");
  assert.equal(result.rssKb, 100);
  assert.equal(result.threads, 2);
  assert.equal(result.startTicks, 50);
});

test("kill rejects critical targets and only allows TERM or KILL", () => {
  const f = fixture();
  for (const [pid, start, signal] of [["1", "50", "TERM"], ["300", "50", "KILL"], ["400", "50", "TERM"], ["100", "50", "STOP"], ["abc", "50", "TERM"]]) {
    const result = run(f, ["kill", pid, start, signal]);
    assert.notEqual(result.status, 0, `${pid} ${signal} unexpectedly allowed`);
  }
  const reused = run(f, ["kill", "100", "999", "TERM"]);
  assert.notEqual(reused.status, 0);
  assert.match(reused.stderr, /identity changed/);

  const allowed = json(run(f, ["kill", "100", "50", "TERM"]));
  assert.deepEqual(allowed, { ok: true, pid: 100, signal: "TERM", dryRun: true });
});
