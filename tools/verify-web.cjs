'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = process.argv[2] || 'build/web';
function exportsAt(folder) {
  for (const name of ['index.html', 'index.js', 'index.wasm', 'index.data', 'odin.js']) {
    assert(fs.existsSync(path.join(folder, name)), `Missing route asset: ${folder}/${name}`);
  }
  const module = new WebAssembly.Module(fs.readFileSync(path.join(folder, 'index.wasm')));
  return new Set(WebAssembly.Module.exports(module).map(entry => entry.name));
}
const player = exportsAt(root);
const creator = exportsAt(path.join(root, 'editor'));
for (const name of ['web_start', 'web_frame', 'web_set_paused', 'web_restart', 'web_set_muted']) {
  assert(player.has(name), `Player entry point missing: ${name}`);
}
for (const name of ['web_editor_toggle', 'web_editor_open', 'web_campaign_import', 'web_campaign_export', 'web_campaign_save', 'web_campaign_buffer']) {
  assert(!player.has(name), `Creator entry point leaked into the player build: ${name}`);
  assert(creator.has(name), `Creator entry point missing: ${name}`);
}
for (const names of [player, creator]) {
  assert(![...names].some(name => name.startsWith('web_qa')), 'QA entry point found in a release build');
}
console.log('Verified separate player and creator routes; player has no editor APIs, both builds exclude QA controls.');
