// viewer-src/ のモジュール間に循環 import が無いことを検査する（TASK-432.3）。
//
// 循環があってもバンドル自体は通るが、モジュール評価順が壊れる。viewer-src には
// 「別モジュールのトップレベル値を評価時に読む」形が実在するため
// （scroll.js が doc-path.js の _mmdDocPath を _createScrollSync へ渡す）、
// 循環すると undefined を掴んだまま起動し、実行時に初めて落ちる。
//
// 依存関係は esbuild の metafile から取る。実際にバンドルする経路そのものを
// 見るので、import 文を独自にパースする実装とずれない。

import path from 'node:path';

import esbuild from 'esbuild';

const scriptDir = import.meta.dirname;
const entry = path.join(scriptDir, '..', 'viewer-src', 'index.js');

const result = esbuild.buildSync({
  entryPoints: [entry],
  bundle: true,
  format: 'iife',
  target: 'safari17',
  metafile: true,
  write: false,
});

// input のキーは実行ディレクトリからの相対パス。viewer-src 配下だけを対象にする
// （ベンダーは classic script 側なので、そもそもグラフに現れない）。
const graph = new Map();
for (const [file, info] of Object.entries(result.metafile.inputs)) {
  if (!file.includes('viewer-src/')) {
    continue;
  }
  graph.set(
    file,
    info.imports.map((i) => i.path).filter((p) => p.includes('viewer-src/')),
  );
}

// 深さ優先で後退辺（いま辿っている経路上のノードへ戻る辺）を探す。
const visited = new Set();
const stack = [];
const onStack = new Set();
const cycles = [];

function visit(node) {
  if (onStack.has(node)) {
    cycles.push([...stack.slice(stack.indexOf(node)), node]);
    return;
  }
  if (visited.has(node)) {
    return;
  }
  visited.add(node);
  stack.push(node);
  onStack.add(node);
  for (const next of graph.get(node) || []) {
    visit(next);
  }
  stack.pop();
  onStack.delete(node);
}

for (const node of graph.keys()) {
  visit(node);
}

if (cycles.length > 0) {
  console.error('viewer-src に循環 import があります:');
  for (const cycle of cycles) {
    console.error('  ' + cycle.join(' -> '));
  }
  process.exit(1);
}

console.log(`viewer-src: 循環 import なし（${graph.size} モジュール）`);
