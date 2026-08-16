// ベンダーライブラリ（npm 依存）の取り込み口。
//
// viewer-bundle.js に同梱するベンダーは必ずこのモジュールを経由して import する。
// 「どのパッケージのどのビルドを使うか」の判断をここ 1 箇所に閉じるため
// （以前は viewer.html が min.js をグローバルとして読み、読み手が
// window.hljs / typeof markdownit の形で散っていた）。
//
// 版の単一情報源は BefoldApp/package.json の devDependencies。
// THIRD_PARTY_LICENSES.md の版表との一致は
// scripts/vendored-deps-versions.sh が検査する。
//
// mermaid だけはここに含めない。3.2MB を実際に図を描く瞬間まで遅延ロードする
// 設計のため、npm の dist をそのまま Resources/mermaid.min.js へコピーし
// （scripts/copy-viewer-vendor.mjs）、mermaid.js が <script> で読み込む。

import DOMPurify from 'dompurify';
// highlight.js は common ビルド（36 言語）。full ビルド（192 言語）は
// バンドルが 1MB 以上増えるため使わない。
import hljs from 'highlight.js/lib/common';
import markdownit from 'markdown-it';

export { DOMPurify, hljs, markdownit };
