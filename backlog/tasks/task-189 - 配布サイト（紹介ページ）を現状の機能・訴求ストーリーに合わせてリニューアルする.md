---
id: TASK-189
title: 配布サイト（紹介ページ）を現状の機能・訴求ストーリーに合わせてリニューアルする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-28 14:30'
updated_date: '2026-07-30 15:08'
labels: []
dependencies:
  - TASK-182
ordinal: 265000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布サイトの紹介ページを、初版作成時から充実した現在の befold の機能・特徴に合わせて刷新する。Cloudflare Workers 移行（TASK-182）後の新サイト基盤の上で行う。

## 背景
初版 LP の作成時点から befold の機能が大きく充実し、紹介している特徴が実態とずれている。訴求すべきユーザー像も明確になった。

## 訴求したいユーザー像とストーリー
- 大量のマークダウンファイルを行き来しているユーザー
- git worktree を使っているユーザー

ストーリーの核: Obsidian では markdown を快適に閲覧できるが、worktree をわざわざ vault に登録するのは面倒。一方 befold はコマンドラインからお手軽に表示でき、worktree 上の markdown もすぐ見られる。この「手軽さ」「worktree との相性」を軸に訴求する。

## やること（概略）
- 現在の機能棚卸しに基づいて紹介する特徴を更新する
- 上記ユーザー像に刺さるストーリー/コピーを反映する
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 紹介ページの特徴一覧が現在の befold の機能実態と一致している
- [x] #2 「大量の markdown を行き来するユーザー」向けの訴求が含まれる
- [x] #3 「worktree ユーザー」向けの訴求（Obsidian/vault 登録の手間との対比、CLI からの手軽表示）が含まれる
- [x] #4 Cloudflare Workers 移行後の新サイト基盤上で公開されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. hero を「大量ファイルの回遊」軸に書き換える（⌘P・サイドバー・タブ/スワイプ、数百ファイルのリポジトリ向け軽量ビューア）
2. philosophy セクションを撤去せず文面を書き換えて統合し、worktree ストーリー（Obsidian の vault 登録の手間との対比／CLI からの手軽表示）をここで語る
3. FEATURES を現行実装の棚卸しに合わせて更新（Quick Open ⌘P・サイドバー/ブックマーク・CLI オプション・git 追跡ファイル経由のリンク解決・大容量分割読み込み・QuickLook 拡張・エンコーディング自動判別 などを反映）
4. JA/EN 両方のコピーを揃える（landing.tsx は二言語 SSR）
5. site のテスト（vitest）とビルドを通す
6. scripts/capture-screenshots.applescript:3 の「GitHub Pages 掲載用の」という古い記述を実態（site/public/images/）に合わせる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: site/src/views/landing.tsx の hero / philosophy / FEATURES を書き換え、site/public/style.css に .philosophy-body code のスタイルを追加。

コピーの根拠となる機能棚卸しは実コードから取得（MainMenuBuilder / FileType / TrackedPathResolver / GitRepository / ContentLoader / QuickOpenModel / OpenCLIOptions / SessionRestorer 等）。FeatureGate.inProgressFeaturesEnabled は本番コードに呼び出し箇所がないため、掲載した機能はすべて stable 出荷済み。誇張を避けた点: ドラッグ&ドロップ未実装なので記載せず、100MB は分割読込対象（Markdown/CSV/TSV/コード）に限る旨がわかる書き方にした。

検証: site で npm run typecheck / npm test（5 files, 44 tests）が通過。wrangler dev (127.0.0.1:8788) で / を実際にレンダリングし、JA/EN 両言語の hero・philosophy・特徴グリッド 12 枚をブラウザのスクリーンショットで目視確認。

副次修正: scripts/capture-screenshots.applescript の出力先が既に存在しない docs/images を指していたため site/public/images に修正（コメントの「GitHub Pages 掲載用」も実態に合わせた）。

旧 GitHub Pages リンク調査の結果: 製品コード・README・アプリ内リンク・CHANGELOG はすべて https://befold.tommy109.workers.dev を参照しており、ユーザーに見える古いリンクは残っていない。docs/index.html は新 URL への意図的なリダイレクト shim、docs/superpowers/ 配下と task-182.5 の github.io 参照は履歴記述なのでそのまま残す。

ユーザー要望により、hero 直下に AI レビュー訴求のセクションを追加（見出し「Claude が設計する。私はそれを befold でレビューする。」）。ターゲットは cursor/vscode ではなくターミナルでコーディングエージェントを使う層。検索流入を狙って本文に Claude Code / Codex の名前を入れ、meta description にも反映した。befold はどちらとも連携していないため、連携を示唆せず「使い方の場面」として書いている。CSS は .philosophy.review で罫線を消し、AI レビューと vault の 2 セクションが 1 ブロックに見えるようにした。再検証: typecheck / test（44 tests）通過、wrangler dev で JA/EN 両言語を目視確認。

Features を 2 層構成に変更（ユーザー指摘）。差別化要素の 6 件のみカード（Quick Open / サイドバー & 行き来 / git を知っているリンク解決 / CLI から開く / ライブリロード / 大きなファイルも開ける）で、残り 6 件は MORE_FEATURES として .feature-list に「名前 — 説明」形式で列挙する。LLM やクローラが拾える情報量を減らさないため、文言は 1 つも削っていない。

QuickLook（スペースキーでプレビュー）をユーザー指摘によりカード側へ移動。カード 7 件・列挙 5 件。7 枚目は 3 列グリッドの 1 トラックを占めるだけで幅は伸びないため CSS 変更は不要だった（wrangler dev で確認）。

スクリーンショット撮り直しとサンプル刷新（ユーザー指示）:

1) capture-screenshots.applescript の不具合を 2 件修正。
   - サイドバー表示が ⌘B のままだった（現在は ⌘S）。さらにサイドバー表示は SidebarStateStore でファイルごとに永続化されるため、トグルでは状態が確定しない。CLI の --sidebar / --no-sidebar を SessionRestorer への override として渡す方式に変更し、起動も open -a から /usr/local/bin/befold へ切り替えた（CLI 未インストール時は明示エラー）。
   - ウィンドウはファイルごとに保存されたフレームで開くため、1280x800 へのリサイズ直後は WKWebView の再レイアウト中で、旧レイアウトと新レイアウトが混ざったフレームが撮れていた（実際に 1 回目の撮影が全滅）。リサイズ後 3s・activate 後 2s に延長して解消。

2) サンプルをエージェントの成果物風に刷新。sample.md を「大きな Markdown を待たされずに開く」設計 spec 形式（背景・計測表・採用案・Mermaid 2 種・Swift/JS コードフェンス・検証・未解決）に書き換え、flowchart.mmd を読み込み判定フローに、sample.csv を計測ログ（22 行、引用符付きカンマと複数行セルを維持）に、diagram.svg を読み込みパイプラインの構成図に差し替えた。diagram.svg に焼き込まれていた旧キャッチコピー "Open a file. Instant rendering." を除去。example.swift（LRU キャッシュ）は既に実プロジェクト寄りなので変更なし。sample.htm は task-178 の再現ケース（charset 宣言なし）のため意図的に非変更。

3) Quick Open のスクリーンショット（screenshot-6.png）を追加し、カルーセルに Markdown の次のスライドとして組み込んだ。浮動パネルでも古いピクセルを写さず正しく撮れることを確認済み。

検証: 6 枚すべてを画像として目視確認（レイアウト破綻なし・全体が収まっている）。typecheck / test（44 tests）通過、wrangler dev でカルーセル 6 スライドを確認。

カルーセルの画像が表示されない不具合を修正（ユーザー指摘）。ソースコードのスライドだけでなく、1 枚目以外の 5 枚すべてが空だった。原因は img の loading="lazy"。スライドは overflow:hidden の中を transform で動かすため Chrome がビューポート付近と判定せず、遅延読み込みが永久に発火しない（DOM 上で complete:false / naturalWidth:0 を確認）。lazy を外して decoding="async" にした。画像 6 枚の合計は 1.1MB。

Quick Open はファイル形式ではないため、SCREENSHOTS に kind:'feature' を追加し、キャプション上部にアクセント色の「機能 / Feature」ラベル（.carousel-kind）を出して形式名のスライドと区別した。

検証: 全 6 枚が complete:true / naturalWidth:1280 になることを DOM で確認。Quick Open スライドのラベル表示と、ソースコードスライドの表示をブラウザで目視確認。

カルーセルのキャプションを調整（ユーザー指摘）。Quick Open のスライドを最後尾へ移動。「機能 / Feature」ラベルは英語圏に伝わりにくいため撤去し、位置と色で区別する方式に変更した（形式名は右下・白、機能は左下・アクセント色。.carousel-caption.feature）。「ソースコード」のカタカナ表記も英語圏には読めないため 'Source Code' に統一し、JA/EN の出し分けをやめた（Mermaid / SVG / Markdown / CSV と同じく両言語共通表記になる）。

検証: DOM 上でキャプションが Mermaid → SVG → Markdown → CSV → Source Code → Quick Open(feature) の順であることを確認し、Quick Open スライドの左下・アクセント色表示をブラウザで目視確認。

カードの見出しを「スペースキーでプレビュー」→「QuickLook 対応」に変更（ユーザー指摘）。EN も操作の説明ではなく機能名に揃えて 'Preview with the Space Bar' → 'QuickLook Support' とした。スペースキーで開ける旨は本文に残っている。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
配布サイトの紹介ページを、現在の befold の機能実態と、ターミナルでコーディングエージェントを使う層に向けた訴求ストーリーに合わせて刷新した。

コピー面では、ヒーローを「Markdown を行き来する。快適に。」に変え、hero 直下に AI レビューのセクション（「Claude が設計する。私は befold でレビューする。」）を新設、従来の philosophy を worktree ユーザー向けストーリー（Obsidian の vault 登録の手間との対比、CLI からの手軽表示）に書き換えた。特徴一覧は実装の棚卸しに基づいて更新し、差別化要素 6 件をカード・残り 6 件を列挙とする 2 層構成にした（掲載情報は削っていない）。ダウンロード導線は配布サイトの絶対 URL に統一し、計測できない GitHub Releases への直リンクを外した。

不具合も 3 件直した。カルーセルの loading=lazy により 1 枚目以外の画像が永久に読み込まれていない問題、本文リンクがブラウザ既定色で暗背景に埋もれる問題、撮影スクリプトのサイドバー指定が ⌘B のままでリサイズ直後の撮影がレイアウト混在になる問題。

サンプルはエージェントの成果物風に刷新し（sample.md を設計 spec、flowchart.mmd を判定フロー、sample.csv を計測ログ、diagram.svg を構成図）、diagram.svg に焼き込まれていた旧キャッチコピーを除去。スクリーンショット 6 枚を撮り直し、Quick Open の 1 枚を追加した。

検証: npm run typecheck / npm test（5 files, 44 tests）通過。wrangler dev で JA/EN 両言語の全セクション・カルーセル 6 スライド・機能カードと列挙・インストール手順をブラウザで目視確認。カルーセル全 6 枚が complete:true / naturalWidth:1280 になることを DOM で確認。生成した 6 枚の PNG も画像として確認した。

受入条件 #4（新サイト基盤上での公開）は PR #341 のマージ時に site.yml が自動デプロイして満たされる。ユーザー判断により、マージ前に完了扱いとした。
<!-- SECTION:FINAL_SUMMARY:END -->
