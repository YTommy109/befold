# パスリンクナビゲーション設計

## 概要

Markdown 本文中のファイルパス文字列を自動検出してクリック可能にし、
befold 内でファイルを開く。リンク経由の遷移は既存の `switchFile` 経路で
NavigationHistory に記録済みであることが調査で判明したため、
履歴まわりはコード変更ではなくテスト追加で担保する。

## 背景

設計書を Markdown で書く際、別の設計書やソースコードへの参照が頻出する。
現状は `[説明](path)` 形式の Markdown リンクと、コードブロック（`pre code`）内の
パス文字列（cmd+click）が対応済み。
しかし本文テキスト中の素のパス文字列（`docs/dev/coding_rule.md`）と、
インラインコード（`` `docs/foo.md` ``、`pre` を伴わない `code`）内のパスは検出されない。

### 調査結果: 履歴記録は既に動作している

<!-- derived-from #背景 -->

当初「リンク経由のファイル切替が履歴に記録されない」ことを前提としていたが、
現行コード（#177 以降）の調査で以下が確認された:

- `handleOpenReference` の同一ウィンドウ経路は `switchFile(to:)` を呼ぶ
  （`ViewerWindowController.swift`）
- `switchFile` は成功時に `sidebar.syncAfterSwitch(to:)` を呼び、そこで
  サイドバーのディレクトリ追従・選択同期・`recordHistory()` がすべて実行される
  （`SidebarNavigator.swift`）
- 履歴エントリは `HistoryEntry(directory:file:)` の `(directory, file)` ペアであり、
  戻る操作でサイドバーのディレクトリも復帰する（`NavigationHistory.swift`）

2026-07-11 に実機確認済み: リンク遷移（同一/別ディレクトリ）で履歴が積まれ、
戻る操作でリンク元ファイル・元ディレクトリ表示に復帰する。

したがって履歴・サイドバー連動に追加実装は不要。逆に `handleOpenReference` 側へ
`recordHistory()` を追加すると、`switchFile` 前に呼んだ場合に遷移前の状態を
誤って積む二重 push リスクがある。**本設計では履歴まわりのプロダクトコードは変更しない。**

## 設計

### 1. パス検出の拡張（viewer.html）

#### 走査範囲の拡張

`_annotatePathRefs` の走査対象を `pre code` 内に加え、以下に広げる:

- `#diagram-wrap` 配下の `p`, `li`, `td`, `th`, `blockquote`, `dt`, `dd` 内のテキストノード
- インラインコード（`pre` を祖先に持たない `code`）内のテキストノード。
  Markdown で最も一般的なパス表記であり、既存の `pre code` 限定ロジックでは拾えない

`td`, `th` を対象に含めるため、CSV プレビュー（`table > td`/`th` としてレンダリングされる）
のセル内パスも副作用ではなく仕様としてリンク化対象になる。

走査時のスキップ条件（`_walkTextNodes` は子要素へ再帰するため、
対象タグの列挙だけでは除外にならない。walk 時のタグ判定として実装する）:

- `<a>` 配下（既にリンクとして処理される。span 化すると二重装飾になる）
- `<pre>` 配下（既存の `pre code` 走査が処理済み）
- `<svg>` / `.mermaid` 配下（mermaid が生成する図中テキストを誤検出しない）
- `.befold-path-ref` 配下（既存ガードを維持。二重ラップ防止）

#### テキストノード長の閾値

`_walkTextNodes` には 1000 文字超のテキストノードをスキップする早期 return がある。
コードブロック前提の最適化だが、本文の段落は 1 テキストノードが容易に 1000 文字を超え、
パスを取りこぼす。閾値は撤廃する（`_PATH_RE` は既知拡張子必須の線形走査であり、
長文でも実行コストは許容範囲）。

#### linkify の fuzzyLink 無効化（実装済み）

markdown-it の `linkify: true` は scheme なしのドメイン風文字列も自動リンク化する。
`.md`（モルドバ）や `.sh`（セントヘレナ）は実在の ccTLD のため、本文中の素のファイル名
（`setup.md` 等）が `http://setup.md` の外部リンクに化け、クリックするとブラウザが開いてしまう
（`.external` 判定自体は正しく、HTML 生成時点の問題）。

`md.linkify.set({ fuzzyLink: false })` で fuzzy 検出のみを無効化する:

- `https://example.com` のような scheme 付き URL の自動リンク化は維持
- `[text](url)` 形式・メールアドレスの自動リンク化も影響なし
- 副作用: scheme なしの `www.example.com` はリンク化されなくなる（`https://` を明示すれば可）

スラッシュなしの素のファイル名は `_PATH_RE` がスラッシュ必須のため本設計でもリンク化されない。
「スラッシュ付きで書けばファイルリンクになる」という整理とする。

#### 正規表現

既存の `_PATH_RE` をそのまま利用。既知拡張子（`.md`, `.swift`, `.mmd` 等）を持ち
スラッシュを含むパスのみマッチするため、本文テキストでも誤検出リスクは低い。

#### クリック動作の統一

コードブロック内のパス参照（`.befold-path-ref`）のクリック動作を `<a>` タグと揃える:

- **現在**: cmd+click で同一ウィンドウ遷移（無修飾は no-op、`newWindow: false` 固定）
- **変更後**: 無修飾クリックで同一ウィンドウ遷移、cmd+click で新規ウィンドウ

本文テキスト・インラインコード内のパス参照も同じ動作。

**注意（破壊的変更）**: 既存の cmd+click は「同一ウィンドウ」だったが、
変更後は「新規ウィンドウ」に意味が反転する。`<a>` リンクとの一貫性を優先する。

#### 存在しないファイルのクリック

無修飾クリックで発火するようになるため、本文中の誤検出パスをクリックすると
既存の not-found アラートが出る。`_PATH_RE` の誤検出リスクが低いこと、
サイレント無視はユーザーが「クリックが効かない」と誤解する懸念があることから、
既存アラートのまま変更しない（スコープ外の項も参照）。

#### スタイリング

セレクタでコンテキストを分離する:

- `pre .befold-path-ref`: カーソルのみ常時 `pointer`（クリック可能の手がかり）。
  下線は cmd 押下時のみ（`.cmd-held pre .befold-path-ref` 側で付与）。
  ホバー色はコードブロックの見た目を保つため pre 内では付けない
  （`pre .befold-path-ref:hover` で無条件に打ち消す）。
  無修飾クリックで遷移するのに見た目が不活性という affordance 不一致の指摘を受け、
  カーソルだけ常時ポインタにする（下線までは付けない）
- それ以外の `.befold-path-ref`（本文・インラインコード）: 常時 `<a>` 風スタイル
  - アンダーライン
  - `cursor: pointer`
  - ホバー時のハイライト

### 2. テスト

#### 履歴統合の回帰テスト（Swift）

`handleOpenReference` 自体のテストは現存しない。以下を `befoldTests/` に追加する:

- リンク遷移（`handleOpenReference` → `.localFile` → `switchFile`）で履歴が積まれ、
  戻る操作でリンク元ファイル・元ディレクトリに復帰する
- 別ディレクトリのファイルへのリンク遷移でサイドバーのディレクトリが追従する
- `newWindow: true` 経路（別ウィンドウで開く）では元ウィンドウの履歴が変化しない

#### パス検出拡張の確認（JS）

viewer.html の JS はプロジェクト規約上、自動テスト対象外（WebView/GUI 層）。
`/webview-smoke` による手動確認項目として以下を追加する:

- 本文段落・リスト・テーブル・インラインコード内のパスがリンク化される
- CSV セル内のパスがリンク化される
- 1000 文字を超える長い段落内のパスもリンク化される
- `<a>` リンク内・mermaid 図内のパス文字列がリンク化されない
- 無修飾クリックで同一ウィンドウ遷移、cmd+click で新規ウィンドウ

### 3. 変更ファイル一覧

| ファイル | 変更内容 |
|---|---|
| `viewer.html` | markdown-it の fuzzyLink 無効化（素のファイル名の外部リンク誤爆を解消。**実装済み**） |
| `viewer.html` | `_annotatePathRefs` の走査範囲を本文テキスト要素・インラインコードに拡張 |
| `viewer.html` | walk 時のスキップ条件（`a` / `pre` / `svg` / `.mermaid`）を追加 |
| `viewer.html` | テキストノード長 1000 文字の早期 return を撤廃 |
| `viewer.html` | `.befold-path-ref` のクリック動作を無修飾クリック対応に変更 |
| `style.css` | `pre` 外の `.befold-path-ref` にリンク風スタイル |
| `befoldTests/` | `handleOpenReference` 経由の履歴・サイドバー連動の回帰テスト |

履歴・サイドバー連動のプロダクトコード（`ViewerWindowController` / `SidebarNavigator`）は
**挙動を変更しない**（前述の調査結果のとおり既存実装で完結している）。
唯一の例外として、テストからエントリポイントへ到達するため
`handleOpenReference` のアクセスレベルを `private` から `internal` に緩和する
（`@testable import` 用。挙動は不変）。

## スコープ外

- 外部 URL（`http://`）のリンク処理（既存のまま `NSWorkspace.shared.open`）
- ファイル存在チェックの UI フィードバック（既存のアラートのまま）
- パス検出の拡張子リストの設定 UI
- シンタックスハイライトのトークン分割をまたぐパスの検出（既存の既知制約のまま）
