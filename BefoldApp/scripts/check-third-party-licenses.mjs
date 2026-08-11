// THIRD_PARTY_LICENSES.md の版表が、実際に同梱している依存と一致しているかを検査する。
//
// 同梱物の版の正は npm（package.json の devDependencies と、実際に入っている
// node_modules）。この表はアプリ内の OSS ライセンス表示（OSSLicensesView）が
// そのまま読むユーザー向けの記載なので、依存を上げたときに更新を忘れると
// 「表示している版と同梱している版が違う」状態になる。手で気づける形ではないため
// 機械で落とす。
//
// 検査するもの:
//   1. npm 由来の各コンポーネント（バンドル同梱・ファイル同梱の両方）について
//      package.json の指定版 == node_modules の実インストール版 == 表の版
//   2. 表の License 欄の SPDX 識別子が、パッケージの license と集合として一致する
//   3. 表に載っている npm 由来の行が上のリストと過不足なく対応する
//   4. Swift 依存（Sparkle / swift-argument-parser）の行が Package.swift に実在する
//      （版は "2.x" のような幅を持つ記載なので、存在だけを見る）
//
// 使い方: npm run check:third-party-licenses
//         （リポジトリルートからは scripts/vendored-deps-versions.sh）

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PACKAGE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
const LICENSES_PATH = join(PACKAGE_DIR, 'BefoldKit', 'Resources', 'THIRD_PARTY_LICENSES.md');

// [THIRD_PARTY_LICENSES.md の Component 名, npm パッケージ名, 同梱のしかた]
const NPM_COMPONENTS = [
  ['Mermaid', 'mermaid', 'Resources/mermaid.min.js へコピー（遅延ロード）'],
  ['markdown-it', 'markdown-it', 'viewer-bundle.js に同梱'],
  ['highlight.js', 'highlight.js', 'viewer-bundle.js に同梱 + テーマ CSS をコピー'],
  ['DOMPurify', 'dompurify', 'viewer-bundle.js に同梱'],
  ['github-markdown-css', 'github-markdown-css', 'Resources/github-markdown.css へコピー'],
];

// Swift 依存は Package.swift の .package(url:) に名前が現れることだけを見る。
const SWIFT_COMPONENTS = [
  ['Sparkle', 'sparkle-project/Sparkle'],
  ['swift-argument-parser', 'apple/swift-argument-parser'],
];

const errors = [];
const rows = new Map();

const licenses = readFileSync(LICENSES_PATH, 'utf8');
for (const line of licenses.split('\n')) {
  const match = /^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|$/.exec(line);
  if (!match || match[1] === 'Component' || /^-+$/.test(match[1])) { continue; }
  rows.set(match[1], { version: match[2], license: match[3] });
}
if (rows.size === 0) {
  errors.push('THIRD_PARTY_LICENSES.md から版表を読み取れない（表の形が変わった可能性）');
}

// "Apache-2.0 / MPL-2.0 (dual)" と "(MPL-2.0 OR Apache-2.0)" を同じものとして比べる。
function spdxIds(text) {
  return new Set((text.match(/[A-Za-z0-9.+-]+-[A-Za-z0-9.+-]+/g) || [])
    .filter((token) => !/^(dual|OR|AND)$/i.test(token)));
}

const declared = JSON.parse(readFileSync(join(PACKAGE_DIR, 'package.json'), 'utf8')).devDependencies;

for (const [component, pkg, shipping] of NPM_COMPONENTS) {
  const row = rows.get(component);
  if (!row) {
    errors.push(`${component}: THIRD_PARTY_LICENSES.md の表に行が無い（${shipping}）`);
    continue;
  }
  const spec = declared[pkg];
  if (!spec) {
    errors.push(`${pkg}: package.json の devDependencies に無い（${shipping}）`);
    continue;
  }
  if (!/^\d+\.\d+\.\d+$/.test(spec)) {
    errors.push(`${pkg}: devDependencies の指定 "${spec}" が版固定でない（同梱物は 1 つの版に固定する）`);
  }
  let meta;
  try {
    // node_modules を直接読む。package.json を "exports" で公開していない
    // パッケージ（dompurify）があり、require.resolve では届かないため。
    meta = JSON.parse(readFileSync(join(PACKAGE_DIR, 'node_modules', pkg, 'package.json'), 'utf8'));
  } catch {
    errors.push(`${pkg}: node_modules に入っていない（npm ci を実行する）`);
    continue;
  }
  if (meta.version !== spec.replace(/^[\^~]/, '')) {
    errors.push(`${pkg}: devDependencies の ${spec} と node_modules の ${meta.version} が食い違う`);
  }
  if (row.version !== meta.version) {
    errors.push(
      `${component}: THIRD_PARTY_LICENSES.md の ${row.version} と実際の ${meta.version} が食い違う`
    );
  }
  const expected = spdxIds(typeof meta.license === 'string' ? meta.license : '');
  const recorded = spdxIds(row.license);
  const sameLicense = expected.size === recorded.size
    && [...expected].every((id) => recorded.has(id));
  if (expected.size > 0 && !sameLicense) {
    errors.push(
      `${component}: ライセンス表記が食い違う（表: ${row.license} / パッケージ: ${meta.license}）`
    );
  }
  console.log(`${component}\t${meta.version}\t${row.license}\t${shipping}`);
}

const packageSwift = readFileSync(join(PACKAGE_DIR, 'Package.swift'), 'utf8');
for (const [component, repo] of SWIFT_COMPONENTS) {
  if (!rows.has(component)) {
    errors.push(`${component}: THIRD_PARTY_LICENSES.md の表に行が無い`);
  }
  if (!packageSwift.includes(repo)) {
    errors.push(`${component}: Package.swift に ${repo} への依存が無い（表の行が古い）`);
  }
}

// 表にあってこちらの一覧に無い行は、依存を外したのに記載だけ残った可能性がある。
const known = new Set([...NPM_COMPONENTS.map((c) => c[0]), ...SWIFT_COMPONENTS.map((c) => c[0])]);
for (const component of rows.keys()) {
  if (!known.has(component)) {
    errors.push(`${component}: 表にあるがスクリプトの一覧に無い（同梱を止めたか、一覧の更新漏れ）`);
  }
}

if (errors.length > 0) {
  for (const message of errors) { console.error(`ERROR: ${message}`); }
  process.exit(1);
}
console.log('OK: THIRD_PARTY_LICENSES.md は実際の依存と一致している');
