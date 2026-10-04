import { readdir, readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { moneyFromKurus } from '../js/utils.js';
for (const directory of ['js','scripts']) for (const file of await readdir(directory)) {
 if (!file.endsWith('.js')) continue;
 const result = spawnSync(process.execPath, ['--check', directory + '/' + file], {encoding:'utf8'});
 assert.equal(result.status,0,result.stderr);
}
for (const page of ['index','game','login','register']) {
 const html = await readFile(page + '.html','utf8');
 for (const match of html.matchAll(/(?:src|href)="((?:css|js)[/][^"#]+)"/g)) await readFile(match[1]);
}
assert.equal(moneyFromKurus('125099'), '1.250,99 ₺');
assert.equal(moneyFromKurus('-1'), '-0,01 ₺');
console.log('PASS: JavaScript syntax, page asset references, integer money formatting.');

