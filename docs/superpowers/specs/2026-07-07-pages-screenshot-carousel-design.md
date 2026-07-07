# GitHub Pages スクリーンショットカルーセル & リボン 設計

<!-- constrained-by ../../index.html -->

## 背景・目的

`docs/index.html`(GitHub Pages紹介ページ)の Screenshot セクションは現状プレースホルダー(「スクリーンショット（後日追加）」)のままで、実画像が未設置。見栄えのするスクリーンショットをカルーセル形式で埋め込み、OSS紹介サイトでよくある GitHub リボンも追加する。あわせて、スクリーンショットを継続的に撮り直せるよう AppleScript による自動撮影スクリプトを整備する。

## スコープ

以下4点を一連のパイプラインとして扱う。

1. `sample/` ディレクトリのブラッシュアップ(スクショ映えする内容に)
2. AppleScript によるスクリーンショット自動撮影
3. `docs/index.html` へのカルーセル埋め込み
4. GitHub リボンの追加

依存関係: 1 → 2 → 3。4は独立して着手可能。

## 1. sample ディレクトリのブラッシュアップ

既存ファイルの内容を確認した結果、`sample/*.mmd`(class/er/flowchart/sequence/state)・`sample.md`・`sample.csv`・`sample.tsv` はすでにbefoldの実アーキテクチャに基づいた内容の濃いサンプルであり、書き直しは不要と判断した。スクリーンショットで見劣りするのは `diagram.svg`(円3つ+テキストのみの明らかなプレースホルダー)のみのため、変更対象はこれに絞る。

| ファイル | 変更方針 |
|---|---|
| `sample/diagram.svg` | 手描き図形サンプルから、befoldらしいアイコン/ロゴ風SVGに差し替え |
| `sample/*.mmd`, `sample/sample.md`, `sample/sample.csv`, `sample/sample.tsv` | 変更なし(すでに実用的な内容) |

## 2. スクリーンショット自動撮影(AppleScript)

`scripts/capture-screenshots.applescript` を新規作成する(テキスト形式、`osascript` で実行、既存の `scripts/*.sh` と同様にリポジトリ管理)。

処理フロー:

1. befold が起動していれば終了し、`open -a befold <sample-file>` で対象ファイルを1つずつ開く
2. `System Events` でウィンドウの位置・サイズを固定値(例: 1280×800)にリサイズ(befold 側の Apple Events 対応・sdef定義は不要。UIスクリプティングのみで実現可能)
3. `keystroke "b" using {command down}` でサイドバー(ファイル一覧、既存の ⌘B ショートカット)を表示させる
4. レンダリング待ち(`delay`)後、`screencapture -l<windowID>` でウィンドウ単体を撮影し `docs/images/screenshot-N.png` に保存
5. 撮影対象は代表5ファイル: `flowchart.mmd`, `sequence.mmd`, `sample.md`, `sample.csv`, ソースコード表示例(任意のソースファイル)

制約・前提:

- **ダークモード統一**: スクリプトからシステム全体のダークモード設定 (`defaults write`) は変更しない。撮影者が事前に手動でダークモードに切り替えておく前提とし、スクリプト冒頭のコメントに明記する。
- **アクセシビリティ権限**: 初回実行時、`System Events` によるUI操作(ウィンドウリサイズ・キーストローク送信)には macOS のアクセシビリティ権限の許可が必要。コードでは制御不可のため、スクリプト内コメントと `scripts/` 配下の説明に注記する。

## 3. GitHub Pages カルーセル埋め込み

`docs/index.html` の `<section class="screenshot">` 内、現在のプレースホルダー `div.screenshot-placeholder` を以下に置き換える。

- 構造: `.carousel` > `.carousel-track`(`docs/images/screenshot-1.png`〜`screenshot-5.png` を横並び) + 左右矢印ボタン + `.carousel-dots`(インジケータ)
- 新規 `docs/carousel.js`(vanilla JS、外部依存なし):
  - 自動再生(4秒間隔で次の画像へ、`transform: translateX()` でスライド)
  - `mouseenter` / `mouseleave` でオートプレイの一時停止/再開
  - 矢印ボタン・ドットクリックによる手動遷移
  - `prefers-reduced-motion: reduce` の場合はアニメーションを抑制
- `docs/style.css` に `.carousel` 関連スタイルを追記。既存のCSS変数(`--color-bg` 等)を再利用し、ライト/ダーク双方に自動追従させる
- `docs/images/.gitkeep` は実画像追加に伴い削除

## 4. GitHub リボン

- `docs/index.html` の `<body>` 直下に `<a class="github-ribbon" href="https://github.com/YTommy109/befold">GitHub</a>` を追加
- `docs/style.css` に `.github-ribbon` を追記。`position: fixed; top: 0; right: 0; transform: rotate(45deg);` の斜め帯をCSSのみで実装(外部画像・ライブラリ不使用)。背景色は既存の `--color-accent` を使用
- 既存の `@media (max-width: 600px)` にサイズ調整を追記(小画面での視認性確保)

## 変更ファイル一覧

| ファイル | 種別 |
|---|---|
| `sample/diagram.svg` | 内容差し替え |
| `scripts/capture-screenshots.applescript` | 新規 |
| `docs/images/screenshot-1.png`〜`screenshot-5.png` | 新規(自動撮影の成果物) |
| `docs/images/.gitkeep` | 削除 |
| `docs/index.html` | screenshotセクション置き換え、GitHubリボン要素追加 |
| `docs/style.css` | carousel / ribbon スタイル追記 |
| `docs/carousel.js` | 新規 |

## 検証方法

- `osascript scripts/capture-screenshots.applescript` を実行し、`docs/images/` に5枚の実画像が生成されることを確認する
- `docs/index.html` をブラウザ(ローカルサーバ経由)で開き、以下を目視確認する:
  - カルーセルの自動再生・ホバー時の一時停止・矢印/ドットによる手動操作
  - GitHub リボンの表示とクリックでのリポジトリ遷移
  - ライトモード/ダークモード双方での見た目
  - 画面幅を縮小した際のレスポンシブ表示

## 非スコープ

- befold アプリ本体への AppleScript スクリプタブル対応(sdef定義、Apple Events実装)は行わない。ウィンドウリサイズ・キーストローク送信は `System Events` のUIスクリプティングのみで実現するため不要
- ダークモードの自動切替え(システム設定変更)は行わない
