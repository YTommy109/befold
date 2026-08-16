// npm 依存のうち「バンドルへ取り込まずファイルのまま同梱するもの」を
// node_modules から BefoldKit/Resources/ へコピーする。
//
// 対象は 2 種類しかない。
//   - mermaid: 3.2MB を実際に図を描く瞬間まで遅延ロードする設計のため、
//     viewer-bundle.js に取り込めない（viewer-src/mermaid.js が <script> で挿す）。
//   - CSS: viewer.html が <link> で読む style.css が @import layer(vendor) で
//     取り込むため、CSS のまま置く必要がある。
//
// それ以外（markdown-it / highlight.js / DOMPurify）は viewer-src/vendor.js から
// import して viewer-bundle.js に含める。ここには足さないこと。
//
// 生成物はコミットする（viewer-bundle.js と同じ扱い）。ソースは常に
// node_modules であり、手で編集しない。ずれは npm run check:viewer-vendor が
// git diff で検出する。

import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const PACKAGE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
const RESOURCES_DIR = join(PACKAGE_DIR, 'BefoldKit', 'Resources');

// [npm パッケージ, パッケージ内のパス, 出力名, バナーを付けるか]
// バナーはミニファイド JS には付けない（mermaid は自前のライセンスコメントを持つ）。
const COPIES = [
  ['mermaid', 'dist/mermaid.min.js', 'mermaid.min.js', false],
  ['github-markdown-css', 'github-markdown.css', 'github-markdown.css', true],
  ['highlight.js', 'styles/github.css', 'github.css', true],
  ['highlight.js', 'styles/github-dark.css', 'github-dark.css', true],
];

function packageDir(name) {
  // package.json を解決の起点にする。エントリポイント（main/exports）は
  // パッケージによって dist の下を指すため、そこからの相対では届かない。
  return dirname(require.resolve(`${name}/package.json`));
}

function banner(name, version) {
  const meta = require(`${name}/package.json`);
  const license = typeof meta.license === 'string' ? meta.license : 'see THIRD_PARTY_LICENSES.md';
  const home = meta.homepage || `https://www.npmjs.com/package/${name}`;
  return `/*! ${name} v${version} | ${license} | ${home} */\n`;
}

for (const [name, from, to, withBanner] of COPIES) {
  const version = require(`${name}/package.json`).version;
  const source = readFileSync(join(packageDir(name), from));
  const output = withBanner ? Buffer.concat([Buffer.from(banner(name, version)), source]) : source;
  writeFileSync(join(RESOURCES_DIR, to), output);
  console.log(`${to} <- ${name}@${version}/${from}`);
}
