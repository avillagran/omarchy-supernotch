const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const qml = fs.readFileSync(path.resolve(__dirname, "..", "MarqueeText.qml"), "utf8");

test("overflow marquee is a continuous two-copy loop", () => {
  assert.match(qml, /id:\s*firstCopy/);
  assert.match(qml, /id:\s*secondCopy/);
  assert.match(qml, /secondCopy[\s\S]*x:\s*root\.scrollX\s*\+\s*root\.cycleW/);
  assert.match(qml, /NumberAnimation on scrollX/);
  assert.match(qml, /running:\s*!root\.fits\s*&&\s*root\.text\.length\s*>\s*0/);
  assert.match(qml, /to:\s*-root\.cycleW/);
  assert.match(qml, /loops:\s*Animation\.Infinite/);
  assert.match(qml, /easing\.type:\s*Easing\.Linear/);
  assert.doesNotMatch(qml, /SequentialAnimation|PauseAnimation/);
});

test("short text stays static and renders only one visible copy", () => {
  assert.match(qml, /firstCopy[\s\S]*x:\s*root\.fits\s*\?\s*0\s*:\s*root\.scrollX/);
  assert.match(qml, /secondCopy[\s\S]*visible:\s*!root\.fits/);
});
