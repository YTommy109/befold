# github-markdown-css 導入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Markdown プレビューを github-markdown-css v5.9.0 で GitHub と同じ見た目にする(表の行間・余白の詰まり問題の根本対応)。

**Architecture:** github-markdown-css(auto バリアント)を `Resources/` にベンダリングし、Markdown レンダリング時のみ `#diagram-wrap` に `markdown-body` クラスを付与する。`style.css` の自前 Markdown スタイルは削除し、背景色差し替え・mermaid 図除外・hljs テーマ競合解消の 3 上書きだけを残す。

**Tech Stack:** github-markdown-css 5.9.0(MIT)/ WKWebView 同梱静的リソース / SwiftPM + XcodeGen

**Spec:** `docs/superpowers/specs/2026-07-04-github-markdown-css-design.md`

## Global Constraints

- github-markdown-css のバージョンは **5.9.0** に固定(auto バリアント `github-markdown.css`)
- 背景色はアプリ現行色を維持する: `--bgColor-default: var(--bg)`(ライト `#fff` / ダーク `#1e1e1e`)。GitHub のダーク背景 `#0d1117` にはしない
- `.mmd`(Mermaid 単体)表示の見た目は一切変えない
- 新規の自動テストは追加しない(WebView/GUI 層はリリース前手動チェックの方針)
- コミットは 1 機能 1 コミット: Task 1 で `feat:` コミットを作り、Task 2〜4 は `git commit --amend --no-edit` で統合する(この機能のコミットを push するまで)
- コミットメッセージは Conventional Commits + 日本語

---

### Task 1: github-markdown.css のベンダリングとリソース登録

**Files:**
- Create: `MmdviewApp/mmdview/Resources/github-markdown.css`
- Modify: `MmdviewApp/Package.swift:24-25`
- Modify: `MmdviewApp/package.json:6-10`

**Interfaces:**
- Consumes: なし
- Produces: バンドルリソース `github-markdown.css`(`.markdown-body` プレフィックスの GitHub スタイル一式。Task 2 が `<link>` で参照、Task 3 が `--bgColor-default` 変数を上書きする)

- [ ] **Step 1: CSS をダウンロードしてバージョンバナーを付ける**

```bash
cd MmdviewApp/mmdview/Resources
curl -sL https://cdn.jsdelivr.net/npm/github-markdown-css@5.9.0/github-markdown.css -o github-markdown.css
{ echo '/*! github-markdown-css v5.9.0 | MIT | https://github.com/sindresorhus/github-markdown-css */'; cat github-markdown.css; } > github-markdown.css.tmp
mv github-markdown.css.tmp github-markdown.css
```

- [ ] **Step 2: 取得内容を検証する**

```bash
head -1 MmdviewApp/mmdview/Resources/github-markdown.css
grep -c 'markdown-body' MmdviewApp/mmdview/Resources/github-markdown.css
grep -m1 -- '--bgColor-default: #0d1117' MmdviewApp/mmdview/Resources/github-markdown.css
```

Expected: 1 行目にバナー、`markdown-body` の出現回数が 100 以上、`--bgColor-default: #0d1117;` が 1 件ヒット(ダーク変数定義の存在確認)。

- [ ] **Step 3: Package.swift にリソースを追記する**

`MmdviewApp/Package.swift` の `resources` 配列、`.copy("Resources/github-dark.css"),`(25 行目)の直後に追加:

```swift
                .copy("Resources/github-markdown.css"),
```

(`project.yml` はディレクトリごとコピーのため変更不要)

- [ ] **Step 4: package.json にバージョンを記録する**

`MmdviewApp/package.json` の `devDependencies` を以下にする(`github-markdown-css` をアルファベット順で追加):

```json
  "devDependencies": {
    "github-markdown-css": "5.9.0",
    "highlight.js": "11.11.1",
    "jest": "^29.7.0",
    "markdown-it": "14.2.0"
  }
```

- [ ] **Step 5: ビルドでリソース同梱を検証する**

Run: `cd MmdviewApp && swift build`
Expected: Build complete(リソース列挙漏れの警告が出ないこと)

- [ ] **Step 6: コミット**

```bash
git add MmdviewApp/mmdview/Resources/github-markdown.css MmdviewApp/Package.swift MmdviewApp/package.json
git commit -m "feat: Markdown プレビューを GitHub 風スタイルにする

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: viewer.html — CSS 読み込みと markdown-body クラスの動的切替

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/viewer.html:16`(link 追加)
- Modify: `MmdviewApp/mmdview/Resources/viewer.html:188-197`(render 内のクラス切替)

**Interfaces:**
- Consumes: Task 1 の `github-markdown.css`
- Produces: Markdown レンダリング時に `#diagram-wrap` が `class="markdown-body"` を持つ DOM 状態(Task 3 のセレクタ `#diagram-wrap.markdown-body` が前提とする)

- [ ] **Step 1: `<link>` を追加する**

`viewer.html` の 16 行目 `<link rel="stylesheet" href="style.css">` の**直前**に追加し、`github-markdown.css → style.css` の順にする(style.css の上書きを後勝ちにするため):

```html
  <link rel="stylesheet" href="github-markdown.css">
  <link rel="stylesheet" href="style.css">
```

- [ ] **Step 2: render() でクラスを切り替える**

`viewer.html` の render() 内(188-197 行)を以下にする:

```js
    if (type === 'mmd') {
      diagramWrap.classList.remove('markdown-body');
      diagramWrap.innerHTML = '<pre class="mermaid">' + _escapeHtml(content) + '</pre>';
    } else {
      // github-markdown-css は .markdown-body プレフィックス前提のため
      // Markdown レンダリング時のみ付与する
      diagramWrap.classList.add('markdown-body');
      if (md) {
        diagramWrap.innerHTML = md.render(content);
      } else {
        diagramWrap.innerHTML = '<p>markdown-it not loaded</p>';
        return;
      }
    }
```

- [ ] **Step 3: 既存 Jest テストが通ることを確認する**

Run: `cd MmdviewApp && npm test`
Expected: PASS(viewer.js の純粋関数テストのみで viewer.html には依存しないが、退行確認として実行)

- [ ] **Step 4: コミット(amend)**

```bash
git add MmdviewApp/mmdview/Resources/viewer.html
git commit --amend --no-edit
```

---

### Task 3: style.css — 自前 Markdown スタイルの削除と上書きの追加

**Files:**
- Modify: `MmdviewApp/mmdview/Resources/style.css:28-31, 55-58, 190-239`

**Interfaces:**
- Consumes: Task 1 の CSS 変数 `--bgColor-default`、Task 2 のクラス付与(`#diagram-wrap.markdown-body`)
- Produces: なし(最終スタイル)

- [ ] **Step 1: 不要になる CSS 変数を削除する**

`style.css` の `:root`(28-31 行)から以下 4 行を削除:

```css
  --code-bg: #f4f4f4;
  --border-subtle: #ddd;
  --table-border: #ccc;
  --link: #007aff;
```

`@media (prefers-color-scheme: dark)` ブロック(55-58 行)から以下 4 行を削除:

```css
    --code-bg: #2d2d2d;
    --border-subtle: #444;
    --table-border: #4a4a4a;
    --link: #4aa3ff;
```

(この 4 変数の参照元は次の Step で削除する 190-239 行ブロックのみ。他の UI では未使用)

- [ ] **Step 2: 自前 Markdown スタイルブロックを上書きブロックに置き換える**

`style.css` 末尾の「Markdown 表示の最小限のダーク対応」コメントから `#diagram-wrap th, #diagram-wrap td { ... }` まで(現 190-239 行)を丸ごと削除し、以下に置き換える:

```css
/*
  Markdown 本文のスタイルは github-markdown-css(.markdown-body)が担う。
  render() が Markdown レンダリング時のみ #diagram-wrap に markdown-body を
  付与する。ここでは背景色のアプリ現行色への差し替えと、mermaid 図・
  hljs テーマとの競合解消だけを上書きする。
*/
#diagram-wrap.markdown-body {
  /* 背景は github-markdown-css の GitHub 色ではなくアプリ現行色を使う */
  --bgColor-default: var(--bg);
  width: 100%;
  max-width: 980px;
}

/* Markdown 内の mermaid 図(pre.mermaid)にはコードブロック背景を付けない */
#diagram-wrap.markdown-body pre.mermaid {
  background: none;
  padding: 0;
}

/* hljs テーマ(.hljs)の背景を無効化し、GitHub と同じ pre の背景色を見せる */
#diagram-wrap.markdown-body code.hljs {
  background: transparent;
}
```

- [ ] **Step 3: 削除した変数の参照が残っていないことを検証する**

Run: `grep -n -e '--code-bg' -e '--border-subtle' -e '--table-border' -e '--link' MmdviewApp/mmdview/Resources/style.css`
Expected: ヒットなし(exit code 1)

- [ ] **Step 4: コミット(amend)**

```bash
git add MmdviewApp/mmdview/Resources/style.css
git commit --amend --no-edit
```

---

### Task 4: 棚卸しドキュメントへの登録

**Files:**
- Modify: `.claude/commands/check-vendored-deps.md:3, 9-14`
- Modify: `.claude/agents/vendored-deps-auditor.md:3, 11, 17-22`

**Interfaces:**
- Consumes: Task 1 のバナー形式(`head -1` で `v5.9.0` が読める)
- Produces: なし

- [ ] **Step 1: check-vendored-deps.md を更新する**

3 行目の対象リストを以下にする:

```markdown
`mermaid.min.js` / `markdown-it.min.js` / `highlight.min.js`(+ テーマ CSS `github.css` / `github-dark.css`、Markdown 本文 CSS `github-markdown.css`)は手動ベンダリングで Dependabot の監視外。
```

「## 1. 同梱バージョンを特定する」のコードブロックを以下にする:

```bash
head -1 MmdviewApp/mmdview/Resources/markdown-it.min.js
head -1 MmdviewApp/mmdview/Resources/github-markdown.css
grep -o '"version":"[0-9.]*"' MmdviewApp/mmdview/Resources/mermaid.min.js | head -1
grep -o 'versionString="[0-9.]*"' MmdviewApp/mmdview/Resources/highlight.min.js | head -1
grep -E 'markdown-it|mermaid|highlight|github-markdown' MmdviewApp/package.json
```

- [ ] **Step 2: vendored-deps-auditor.md を更新する**

frontmatter の `description`(3 行目)を以下にする:

```markdown
description: 手動ベンダリングされた同梱 JS/CSS ライブラリ(mermaid / markdown-it / highlight.js / github-markdown-css)のバージョンずれと既知脆弱性を監査する。リリース前や依存を気にするときに使う。
```

「## 背景」の 1 文目(11 行目)を以下にする:

```markdown
`mermaid.min.js`・`markdown-it.min.js`・`highlight.min.js`・`github-markdown.css`(+ hljs テーマ CSS)は `MmdviewApp/mmdview/Resources/` に
```

「## 手順」1. のバージョン特定リストに以下を追加(`head -1 ... markdown-it.min.js` の行の直後):

```markdown
   - `head -1 MmdviewApp/mmdview/Resources/github-markdown.css`（先頭バナー）
```

- [ ] **Step 3: コミット(amend)**

```bash
git add .claude/commands/check-vendored-deps.md .claude/agents/vendored-deps-auditor.md
git commit --amend --no-edit
```

---

### Task 5: 手動検証(リリース前手動チェック方針に従う)

**Files:**
- 参照のみ: `sample/sample.md`(表・mermaid ブロック・swift/javascript コードブロックを含む)、`sample/flowchart.mmd`

**Interfaces:**
- Consumes: Task 1〜4 のすべての変更
- Produces: 検証済みの最終状態

- [ ] **Step 1: ビルドして起動する**

`/run` スキル(または `cd MmdviewApp && swift build` 後にアプリ起動)で `sample/sample.md` を開く。

- [ ] **Step 2: ライトモードで確認する**

チェック項目:
1. 表: 行間がゆったりし(セル `line-height: 1.5`)、偶数行にゼブラ縞、ヘッダが太字
2. 段落・見出し・リストに GitHub 同等の余白(16px)がある
3. コードブロック: 背景が GitHub の muted 色(`#f6f8fa` 系)で、シンタックスハイライトの配色が崩れていない
4. mermaid ブロックが図として描画され、図の背後にコードブロック風の背景が**付かない**
5. ページ背景がアプリ現行色(白)のまま

- [ ] **Step 3: ダークモードで確認する**

システム設定(またはアプリ切替)でダークにして Step 2 と同じ 5 項目を確認。特に:
- ページ背景が `#1e1e1e`(GitHub の `#0d1117` ではない)
- 表の罫線・ゼブラ縞・コードブロック背景がダーク配色で読める

- [ ] **Step 4: .mmd 単体表示の無変化を確認する**

`sample/flowchart.mmd` を開き、従来どおり図が中央に表示されること(背景・余白に変化がないこと)を確認。ズーム(Cmd +/−、リセット)も動作確認。

- [ ] **Step 5: 検証結果を報告する**

問題があれば修正して該当 Task に戻る。すべて OK なら完了報告(コミットは Task 4 までで完成済み。push はユーザー指示があるまで行わない)。
