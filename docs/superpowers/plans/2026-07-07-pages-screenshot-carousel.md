# GitHub Pages スクリーンショットカルーセル & リボン Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub Pages 紹介ページ(`docs/index.html`)にスクリーンショットカルーセルと GitHub リボンを追加し、それを継続的に再撮影できる AppleScript を整備する。

**Architecture:** `sample/diagram.svg` を見栄えの良い内容に差し替え、`scripts/capture-screenshots.applescript` で `sample/` の代表ファイルを befold で開いてウィンドウを固定サイズ・位置にリサイズし `screencapture` で撮影、`docs/images/` に格納する。`docs/index.html` の Screenshot セクションを vanilla JS 製の軽量カルーセル(`docs/carousel.js`)に置き換え、CSS のみで実装した GitHub リボンを追加する。

**Tech Stack:** AppleScript(`osascript`)、vanilla JavaScript(ビルドステップなし)、CSS カスタムプロパティ(既存 `docs/style.css` の踏襲)。

## Global Constraints

- 新規の外部依存(CDN、npmパッケージ)は追加しない(既存の `docs/` は依存ゼロの素 HTML/CSS/JS)
- `sample/*.mmd`, `sample/sample.md`, `sample/sample.csv`, `sample/sample.tsv` は変更しない(設計時点の調査で既に内容が充実していると判断済み)
- befold アプリ本体(Swift側)への変更は行わない。AppleScript は `System Events` によるUIスクリプティングのみで実現し、sdef/Apple Events 対応は追加しない
- ダークモードの自動切替え(`defaults write` 等でのシステム設定変更)は行わない。撮影者が事前に手動でダークモードにしておく前提とする
- `docs/` 配下は GUI/静的サイト層であり、本プロジェクトの既存テスト規約(WebView/GUI層は自動テスト対象外・リリース前手動チェック)に倣い、`carousel.js` の自動テストは追加しない。動作確認はブラウザでの手動確認とする
- AppleScript の実行(実際のスクリーンショット撮影)には macOS のGUIセッション・Accessibility 権限・befold.app のインストール済み環境が必要。構文検証は自動化するが、実撮影の実行はその場のマシンで対話的に行う

---

## ファイル構成

| ファイル | 責務 |
|---|---|
| `sample/diagram.svg` | 差し替え。befoldらしいアイコン/ロゴ風SVG |
| `scripts/capture-screenshots.applescript` | 新規。sample内5ファイルを開き、ウィンドウを固定サイズにして`docs/images/`に撮影保存 |
| `docs/carousel.js` | 新規。カルーセルの自動再生・手動操作ロジック(vanilla JS) |
| `docs/index.html` | Screenshotセクションをカルーセル構造に置き換え、GitHubリボン要素を追加 |
| `docs/style.css` | `.carousel*` / `.github-ribbon` スタイルを追記、不要になった `.screenshot-placeholder` を削除 |
| `docs/images/screenshot-1.png`〜`screenshot-5.png` | AppleScript実行により生成される撮影成果物(バイナリ、git管理) |
| `docs/images/.gitkeep` | 削除(実画像が入るため不要) |

---

### Task 1: `sample/diagram.svg` を差し替える

**Files:**
- Modify: `sample/diagram.svg`

**Interfaces:**
- Consumes: なし
- Produces: なし(他タスクから参照されない独立ファイル)

- [ ] **Step 1: 新しいSVGを書く**

現在の `sample/diagram.svg` は円3つとテキストのみの簡素なサンプル。befold のコンセプト(ファイルを開くだけで即レンダリングされる、静かで快適なビューア)を表現した、ウィンドウ+再生(リロード)アイコン風のSVGに差し替える。

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300" viewBox="0 0 400 300">
  <rect width="400" height="300" fill="#1a1a1a" rx="12"/>
  <rect x="24" y="24" width="352" height="252" rx="8" fill="#2a2a2a" stroke="#3a3a3a" stroke-width="1.5"/>
  <circle cx="44" cy="44" r="5" fill="#ff5f57"/>
  <circle cx="60" cy="44" r="5" fill="#febc2e"/>
  <circle cx="76" cy="44" r="5" fill="#28c840"/>
  <line x1="24" y1="60" x2="376" y2="60" stroke="#3a3a3a" stroke-width="1"/>
  <g transform="translate(150, 110)">
    <circle cx="50" cy="50" r="48" fill="none" stroke="#4da6ff" stroke-width="6"/>
    <path d="M 50 20 A 30 30 0 1 1 20 50" fill="none" stroke="#4da6ff" stroke-width="6" stroke-linecap="round"/>
    <path d="M 20 50 L 10 38 L 30 34 Z" fill="#4da6ff"/>
  </g>
  <text x="200" y="250" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="20" font-weight="600" fill="#f0f0f0">befold</text>
  <text x="200" y="272" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="12" fill="#aaa">Open a file. Instant rendering.</text>
</svg>
```

- [ ] **Step 2: SVGが整形式であることを検証する**

Run: `xmllint --noout sample/diagram.svg`
Expected: 何も出力されず、終了コード0(整形式のXMLであることの確認。エラーがあれば `xmllint` がエラー内容を出力する)

- [ ] **Step 3: befoldで開いて見た目を確認する(手動)**

Run: `open -a befold sample/diagram.svg`
Expected: ウィンドウ枠風の角丸矩形の中に、右下方向へ弧を描く矢印アイコン(リロードを想起させる意匠)と "befold" のロゴテキストが表示される。崩れやレイアウト破綻がないことを目視確認する。

- [ ] **Step 4: コミット**

```bash
git add sample/diagram.svg
git commit -m "chore: サンプルSVGをbefoldらしいアイコン風デザインに差し替える"
```

---

### Task 2: `scripts/capture-screenshots.applescript` を作成する

**Files:**
- Create: `scripts/capture-screenshots.applescript`

**Interfaces:**
- Consumes: `sample/flowchart.mmd`, `sample/sequence.mmd`, `sample/sample.md`, `sample/sample.csv`(いずれも既存、変更なし)
- Produces: `docs/images/screenshot-1.png`〜`screenshot-5.png`(実行時に生成。Task 3のカルーセル実装がこのパス名を前提にする)

- [ ] **Step 1: AppleScriptを書く**

```applescript
-- scripts/capture-screenshots.applescript
--
-- befold の sample/ 配下のファイルを開き、GitHub Pages 掲載用の
-- スクリーンショットを docs/images/ に自動生成する。
--
-- 事前準備:
--   1. macOS をダークモードに切り替えておくこと(システム設定 > 外観 > ダーク)。
--      このスクリプトはダークモードの切り替えを行わない。
--   2. スクリーンショット領域(原点 100,100 / 1280x800)が画面に収まる
--      解像度のディスプレイを使用すること。
--   3. 初回実行時、システム設定 > プライバシーとセキュリティ > アクセシビリティ で
--      実行元(ターミナル / スクリプトエディタ)にUI操作の許可を与えること。
--   4. befold.app がインストール済みであること。
--   5. 撮影対象領域に他アプリのウィンドウが重ならないようにしておくこと。
--
-- 実行方法:
--   osascript scripts/capture-screenshots.applescript

set scriptPosixPath to POSIX path of (path to me)
set scriptsDir to do shell script "dirname " & quoted form of scriptPosixPath
set repoRoot to do shell script "dirname " & quoted form of scriptsDir
set sampleDir to repoRoot & "/sample"
set imagesDir to repoRoot & "/docs/images"

set windowX to 100
set windowY to 100
set windowWidth to 1280
set windowHeight to 800
set captureRect to (windowX as string) & "," & (windowY as string) & "," & (windowWidth as string) & "," & (windowHeight as string)

-- {ファイル名, 出力ファイル名, サイドバーを表示するか, ソース表示に切替するか}
set targets to {¬
    {"flowchart.mmd", "screenshot-1.png", true, false}, ¬
    {"sequence.mmd", "screenshot-2.png", false, false}, ¬
    {"sample.md", "screenshot-3.png", false, false}, ¬
    {"sample.csv", "screenshot-4.png", false, false}, ¬
    {"sample.md", "screenshot-5.png", false, true}}

do shell script "mkdir -p " & quoted form of imagesDir

repeat with targetItem in targets
    set fileName to item 1 of targetItem
    set outputName to item 2 of targetItem
    set showSidebar to item 3 of targetItem
    set showSource to item 4 of targetItem

    set filePath to sampleDir & "/" & fileName
    set outputPath to imagesDir & "/" & outputName

    -- 前回起動していれば終了してクリーンな状態にする
    tell application "System Events"
        if exists (process "befold") then
            tell application "befold" to quit
            delay 1
        end if
    end tell

    do shell script "open -a befold " & quoted form of filePath
    delay 2

    tell application "System Events"
        tell process "befold"
            set position of window 1 to {windowX, windowY}
            set size of window 1 to {windowWidth, windowHeight}
        end tell
    end tell
    delay 1

    if showSidebar then
        tell application "System Events" to keystroke "b" using {command down}
        delay 1
    end if

    if showSource then
        tell application "System Events" to keystroke "u" using {command down}
        delay 1
    end if

    tell application "befold" to activate
    delay 1

    do shell script "screencapture -x -R" & captureRect & " " & quoted form of outputPath
end repeat

tell application "befold" to quit
```

- [ ] **Step 2: 構文を検証する(GUI操作なしで実行可能)**

Run: `osacompile -o /tmp/capture-screenshots-check.scpt scripts/capture-screenshots.applescript`
Expected: エラーなく終了し、`/tmp/capture-screenshots-check.scpt` が生成される(構文エラーがあれば `osacompile` がエラー行を報告する)

- [ ] **Step 3: 検証用の一時ファイルを削除する**

Run: `rm -f /tmp/capture-screenshots-check.scpt`

- [ ] **Step 4: コミット**

```bash
git add scripts/capture-screenshots.applescript
git commit -m "feat: スクリーンショット自動撮影用のAppleScriptを追加する"
```

**注記:** このタスクでは構文検証のみを行う。実際にウィンドウを操作してスクリーンショットを生成する実行(Task 5)は、GUIセッション・Accessibility権限・befold.appのインストールが揃った対話的な環境で行う。

---

### Task 3: GitHub Pages にカルーセルを実装する

**Files:**
- Create: `docs/carousel.js`
- Modify: `docs/index.html:49-55`(Screenshotセクション、末尾の `<script>` タグ手前に `<script src="carousel.js"></script>` を追加)
- Modify: `docs/style.css`(`.screenshot-placeholder` ルールを削除し、`.carousel*` ルールを追加)
- Delete: `docs/images/.gitkeep`

**Interfaces:**
- Consumes: `docs/images/screenshot-1.png`〜`screenshot-5.png`(パス名を前提にした`<img>`参照。実ファイルはTask 5で`scripts/capture-screenshots.applescript`を実行して生成されるため、本タスク実行時点では未生成でも構造実装は可能)
- Produces: `.carousel` DOM構造(Task 4のリボン実装とは独立)

- [ ] **Step 1: `docs/carousel.js` を書く**

```javascript
(function () {
  'use strict';

  function initCarousel(root) {
    var track = root.querySelector('.carousel-track');
    var slides = Array.prototype.slice.call(root.querySelectorAll('.carousel-slide'));
    var dotsContainer = root.querySelector('.carousel-dots');
    var prevButton = root.querySelector('.carousel-prev');
    var nextButton = root.querySelector('.carousel-next');
    var currentIndex = 0;
    var autoplayTimer = null;
    var autoplayIntervalMs = 4000;
    var prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    var dots = slides.map(function (_, index) {
      var dot = document.createElement('button');
      dot.className = 'carousel-dot';
      dot.type = 'button';
      dot.setAttribute('aria-label', 'Slide ' + (index + 1));
      dot.addEventListener('click', function () {
        goToSlide(index);
      });
      dotsContainer.appendChild(dot);
      return dot;
    });

    function render() {
      track.style.transform = 'translateX(-' + (currentIndex * 100) + '%)';
      dots.forEach(function (dot, index) {
        dot.classList.toggle('active', index === currentIndex);
      });
    }

    function goToSlide(index) {
      currentIndex = (index + slides.length) % slides.length;
      render();
    }

    function nextSlide() {
      goToSlide(currentIndex + 1);
    }

    function prevSlide() {
      goToSlide(currentIndex - 1);
    }

    function startAutoplay() {
      if (prefersReducedMotion) return;
      stopAutoplay();
      autoplayTimer = window.setInterval(nextSlide, autoplayIntervalMs);
    }

    function stopAutoplay() {
      if (autoplayTimer !== null) {
        window.clearInterval(autoplayTimer);
        autoplayTimer = null;
      }
    }

    if (prevButton) prevButton.addEventListener('click', prevSlide);
    if (nextButton) nextButton.addEventListener('click', nextSlide);
    root.addEventListener('mouseenter', stopAutoplay);
    root.addEventListener('mouseleave', startAutoplay);

    render();
    startAutoplay();
  }

  document.addEventListener('DOMContentLoaded', function () {
    var root = document.querySelector('.carousel');
    if (root) initCarousel(root);
  });
})();
```

- [ ] **Step 2: `docs/index.html` のScreenshotセクションを置き換える**

`docs/index.html:49-55` の以下のブロックを:

```html
  <!-- Screenshot -->
  <section class="screenshot">
    <div class="screenshot-placeholder">
      <span lang="ja">スクリーンショット（後日追加）</span>
      <span lang="en" hidden>Screenshot (coming soon)</span>
    </div>
  </section>
```

以下に置き換える:

```html
  <!-- Screenshot -->
  <section class="screenshot">
    <div class="carousel">
      <div class="carousel-track">
        <div class="carousel-slide"><img src="images/screenshot-1.png" alt="Mermaid flowchart in befold" loading="lazy"></div>
        <div class="carousel-slide"><img src="images/screenshot-2.png" alt="Mermaid sequence diagram in befold" loading="lazy"></div>
        <div class="carousel-slide"><img src="images/screenshot-3.png" alt="Markdown preview in befold" loading="lazy"></div>
        <div class="carousel-slide"><img src="images/screenshot-4.png" alt="CSV table view in befold" loading="lazy"></div>
        <div class="carousel-slide"><img src="images/screenshot-5.png" alt="Source code view in befold" loading="lazy"></div>
      </div>
      <button class="carousel-prev" type="button" aria-label="Previous screenshot">‹</button>
      <button class="carousel-next" type="button" aria-label="Next screenshot">›</button>
      <div class="carousel-dots"></div>
    </div>
  </section>
```

- [ ] **Step 3: `<script src="carousel.js"></script>` を読み込ませる**

`docs/index.html` の既存 `<script>` タグ(`function switchLang...` を含むインラインスクリプト)の直前に追加:

```html
<script src="carousel.js"></script>
<script>
function switchLang(lang) {
```

- [ ] **Step 4: `docs/style.css` の `.screenshot-placeholder` を削除し、カルーセルスタイルを追加する**

以下のブロックを削除する:

```css
.screenshot-placeholder {
  background: var(--color-surface);
  border: 2px dashed var(--color-border);
  border-radius: var(--radius);
  padding: 4rem 2rem;
  color: var(--color-text-secondary);
  font-size: 0.875rem;
}
```

`.screenshot` ルールの直後に以下を追加する:

```css
.carousel {
  position: relative;
  overflow: hidden;
  border-radius: var(--radius);
  border: 1px solid var(--color-border);
}

.carousel-track {
  display: flex;
  transition: transform 0.5s ease;
}

@media (prefers-reduced-motion: reduce) {
  .carousel-track {
    transition: none;
  }
}

.carousel-slide {
  flex: 0 0 100%;
}

.carousel-slide img {
  display: block;
  width: 100%;
  height: auto;
}

.carousel-prev,
.carousel-next {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  background: rgba(0, 0, 0, 0.5);
  color: #fff;
  border: none;
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 50%;
  font-size: 1.5rem;
  cursor: pointer;
  line-height: 1;
}

.carousel-prev {
  left: 1rem;
}

.carousel-next {
  right: 1rem;
}

.carousel-prev:hover,
.carousel-next:hover {
  background: rgba(0, 0, 0, 0.75);
}

.carousel-dots {
  display: flex;
  justify-content: center;
  gap: 0.5rem;
  padding: 1rem 0;
  background: var(--color-surface);
}

.carousel-dot {
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 50%;
  border: none;
  background: var(--color-border);
  cursor: pointer;
  padding: 0;
}

.carousel-dot.active {
  background: var(--color-accent);
}
```

- [ ] **Step 5: `docs/images/.gitkeep` を削除する**

```bash
git rm docs/images/.gitkeep
```

- [ ] **Step 6: HTMLの整形式を検証する**

Run: `xmllint --html --noout docs/index.html`
Expected: 致命的な構文エラーが出力されない(HTML5の`<img>`単体タグ等についてはxmllintのHTMLパーサが警告なく解釈する。深刻なタグ不整合がないことを確認する)

- [ ] **Step 7: ブラウザで構造を確認する(手動、画像はTask 5実行前は表示されない)**

Run: `open docs/index.html`
Expected: Screenshotセクションにカルーセルの外枠(矢印ボタン・ドットインジケータ)が表示される。画像は `docs/images/screenshot-*.png` が未生成のため壊れて見えるのが正常(Task 5で解消する)。ブラウザの開発者コンソールにJSエラーが出ていないことを確認する。矢印ボタン・ドットをクリックしてスライドが切り替わることを確認する。

- [ ] **Step 8: コミット**

```bash
git add docs/carousel.js docs/index.html docs/style.css docs/images/.gitkeep
git commit -m "feat: GitHub Pagesにスクリーンショットカルーセルを実装する"
```

---

### Task 4: GitHub リボンを実装する

**Files:**
- Modify: `docs/index.html`(`<body>` 直後にリボン要素を追加)
- Modify: `docs/style.css`(`.github-ribbon` を追加、`@media (max-width: 600px)` に調整を追記)

**Interfaces:**
- Consumes: なし(Task 3とは独立)
- Produces: なし

- [ ] **Step 1: `docs/index.html` の `<body>` 直後にリボンを追加する**

```html
<body>

<a class="github-ribbon" href="https://github.com/YTommy109/befold" target="_blank" rel="noopener" aria-label="View source on GitHub">
  <span>GitHub</span>
</a>

<header>
```

- [ ] **Step 2: `docs/style.css` に `.github-ribbon` を追加する**

`footer a:hover` ルールの後に追加:

```css
.github-ribbon {
  position: fixed;
  top: 0;
  right: 0;
  z-index: 200;
  overflow: hidden;
  width: 150px;
  height: 150px;
  pointer-events: none;
}

.github-ribbon span {
  position: absolute;
  display: block;
  width: 220px;
  padding: 0.5rem 0;
  top: 38px;
  right: -50px;
  transform: rotate(45deg);
  background: var(--color-accent);
  color: #fff;
  text-align: center;
  font-size: 0.8125rem;
  font-weight: 600;
  text-decoration: none;
  pointer-events: auto;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
}

.github-ribbon span:hover {
  background: var(--color-accent-hover);
}
```

- [ ] **Step 3: 既存の `@media (max-width: 600px)` にリボンの縮小ルールを追記する**

```css
@media (max-width: 600px) {
  .hero h2 {
    font-size: 1.75rem;
  }

  .hero p {
    font-size: 1rem;
  }

  .feature-grid {
    grid-template-columns: 1fr;
  }

  .github-ribbon {
    width: 100px;
    height: 100px;
  }

  .github-ribbon span {
    width: 150px;
    padding: 0.35rem 0;
    top: 25px;
    right: -40px;
    font-size: 0.6875rem;
  }
}
```

- [ ] **Step 4: HTMLの整形式を検証する**

Run: `xmllint --html --noout docs/index.html`
Expected: 致命的な構文エラーが出力されない

- [ ] **Step 5: ブラウザで確認する(手動)**

Run: `open docs/index.html`
Expected: 右上に斜めの「GitHub」リボンが表示される。クリックするとGitHubリポジトリが新しいタブで開く。ブラウザ幅を600px以下に狭めるとリボンが縮小表示される。

- [ ] **Step 6: コミット**

```bash
git add docs/index.html docs/style.css
git commit -m "feat: GitHub PagesにGitHubリボンを追加する"
```

---

### Task 5: スクリーンショットを生成し結合検証する

**Files:**
- Produces: `docs/images/screenshot-1.png`〜`screenshot-5.png`

**Interfaces:**
- Consumes: Task 2 の `scripts/capture-screenshots.applescript`、Task 3/4 で完成した `docs/index.html`
- Produces: なし(最終成果物の確認)

このタスクは GUI セッション上で対話的に実行する。Accessibility 権限が未許可の場合、初回実行時に許可ダイアログが表示されるため、許可後に再実行する。

- [ ] **Step 1: ダークモードに切り替える(手動)**

システム設定 > 外観 > ダーク に切り替える。

- [ ] **Step 2: スクリーンショット撮影スクリプトを実行する**

Run: `osascript scripts/capture-screenshots.applescript`
Expected: befold のウィンドウが5回開き直され、各回でウィンドウが1280x800にリサイズされた後、`docs/images/screenshot-1.png`〜`screenshot-5.png` が生成される。実行が権限エラーで失敗した場合は、システム設定 > プライバシーとセキュリティ > アクセシビリティ で実行元(ターミナル)を許可してから再実行する。

- [ ] **Step 3: 生成された画像を確認する**

Run: `ls -la docs/images/screenshot-*.png && sips -g pixelWidth -g pixelHeight docs/images/screenshot-1.png`
Expected: 5ファイルが存在し、`screenshot-1.png` の `pixelWidth`/`pixelHeight` が撮影解像度(Retinaディスプレイの場合は 2560x1600 相当、非Retinaの場合は 1280x800)になっている

- [ ] **Step 4: ブラウザで最終確認する(手動)**

Run: `open docs/index.html`
Expected:
  - カルーセルに5枚の実スクリーンショットが表示され、4秒間隔で自動的に切り替わる
  - カルーセルにマウスホバーすると自動再生が一時停止し、離れると再開する
  - 矢印ボタン・ドットクリックで手動遷移できる
  - ブラウザの外観をライト/ダーク切り替えても崩れずに表示される(`docs/style.css` のCSS変数追従)
  - 右上のGitHubリボンが表示され、クリックでリポジトリに遷移する
  - ウィンドウ幅を600px以下に狭めてもレイアウトが破綻しない

- [ ] **Step 5: 生成された画像をコミットする**

```bash
git add docs/images/screenshot-1.png docs/images/screenshot-2.png docs/images/screenshot-3.png docs/images/screenshot-4.png docs/images/screenshot-5.png
git commit -m "chore: GitHub Pages掲載用のスクリーンショットを追加する"
```
