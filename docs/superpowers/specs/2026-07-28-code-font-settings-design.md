# ソースコードビューのフォント設定 — 設計

<!-- derived-from ./../../../.claude/CLAUDE.md -->

> **これは 2026-07-28 時点の設計スナップショットです。**
> 現在の仕様は [`docs/dev/native-app-design.md`](../../dev/native-app-design.md)
> が単一の情報源。この文書は当時の意図と検討経緯を残すためのもので、
> 現在の実装と食い違っていることがある。着手前に必ずコードで裏を取ること。

## 背景

befold には3種のビュー（サイドバー / Markdown・mermaid プレビュー / ソースコードビュー）があるが、
フォントはすべて macOS システムフォントに追従、または CSS でハードコードされており、
ユーザーが切り替える手段がない。

現状の整理（調査結果）:

- **サイドバー**: SwiftUI の `.caption`/`.headline` 等セマンティックスタイル。システムフォント追従（固定サイズなし）。
- **プレビュー本文**: サイズは「システム本文サイズ → CSS 変数 `--mmd-markdown-font-size`」の注入パイプラインで追従。
  さらにズーム（`ZoomStore`）がファイル単位で効く。font-family は `github-markdown.css` の
  `--fontStack-sansSerif` をハードコード。
- **ソースコードビュー**: `.code-body` スコープ。等幅は `github-markdown.css` の `--fontStack-monospace`
  （`ui-monospace, SFMono-Regular, SF Mono, Menlo, …`）を継承。サイズは本文 × 0.75em（既定 16px → 12px）。
- **mermaid / svg**: テーマ既定フォント。フォント設定の対象外。
- 注入土台: `ViewerBridge.systemFontSizeScript` → `ViewerRenderer`（`atDocumentStart` の `WKUserScript`）
  → `viewer.js`/`viewer-main.js` が CSS 変数へ反映、という経路が既にある。font-**family** 用変数は未整備。
- Settings/Preferences の UI・メニューは未実装。UserDefaults 保存は `HiddenFilesPreference` 型が定番。
- アプリは AppKit ライフサイクル（`AppDelegate` 起点、`MainMenuBuilder` が手組み）。
  SwiftUI の `Settings` scene は使えないため設定ウィンドウは自前で用意する。

## 目的

ソースコードビューの**等幅フォントのファミリーとサイズ**をユーザーが設定できるようにする。
「ソースコードだけ等幅で、少し小さめにして情報量を増やしたい」という要求に応える。

サイドバー・プレビュー本文・mermaid/svg は対象外（システム追従・ズームで十分）。

## スコープ

### 対象

- 設定項目は2つのみ:
  1. **等幅フォントのファミリー**（等幅フォントのキュレートリストから選択、または「システム既定」）
  2. **フォントサイズ（絶対 pt）**
- ファミリーの適用先: **ソースコードビュー + Markdown プレビュー内のコード（コードブロック/インラインコード）両方**
  （見た目の等幅を揃える。ファミリーのみ連動）。
- サイズの適用先: **ソースコードビューのみ**。プレビュー内コードは従来どおり本文 × 0.75em を維持。
- 設定はグローバル（アプリ全体、ファイル単位ではない）。
- 変更は開いている全ウィンドウへライブ反映する。
- ズームは従来どおり上乗せで効く（本設定はベースサイズを決めるだけ）。
- 開発中はフィーチャーゲート（TASK-180 の `FeatureGate.inProgressFeaturesEnabled`）で囲い、
  dev/DEBUG ビルドでのみ設定メニュー・ウィンドウを露出する。本機能は同時に
  **フィーチャーゲート機構そのものの最初の実利用者（検証台）**を兼ねる。

### 非対象

- サイドバーのフォント/サイズ設定。
- プレビュー本文のフォント/サイズ設定（サイズは既存のシステム追従＋ズームで足りる）。
- mermaid / svg のフォント。
- プレビュー内コードの**サイズ**をこの設定から変えること（ファミリーのみ連動）。
- 行間・タブ幅・リガチャ等の詳細タイポグラフィ設定。

## 設定項目の仕様

| 項目 | 型 | 既定値 | 適用先 |
| --- | --- | --- | --- |
| フォントファミリー | フォント名 or 「システム既定」センチネル | システム既定 | ソースビュー + プレビュー内コード |
| フォントサイズ | 絶対 pt（Double または Int） | 現状の見た目に近い値（コード 12px ≒ **9pt**） | ソースビューのみ |

- **キュレートリスト**: `NSFontManager` で等幅判定できるシステム内フォント名の一覧。先頭に「システム既定」項目を置く。
  等幅以外を出さないので選び間違いが起きない。
- 「システム既定」を選ぶと、ファミリーは既存のハードコード等幅スタック（`--fontStack-monospace`）へフォールバックする。
- サイズの許容範囲は 6〜32pt 程度にクランプ（UI 側で下限・上限）。
- 既定サイズは現状の見た目（16px 基準の 0.75 倍 = 12px ≒ 9pt）に合わせ、設定未変更ユーザーの表示を変えない。

## アーキテクチャ

### コンポーネント

1. **`CodeFontPreference`（新規, befold/App）**
   - `HiddenFilesPreference` と同型。`UserDefaults` を DI し、キー単位で読み書き。`didSet` で永続化。
   - 保持する値: `fontFamily: String?`（nil = システム既定）、`fontSizePoints: Double`。
   - キー例: `CodeFontFamily`, `CodeFontSizePoints`。
   - `@MainActor @Observable` とし、設定ウィンドウと描画注入の双方から参照する。

2. **`MonospaceFontCatalog`（新規, 純粋ロジック）**
   - `NSFontManager`（または `CTFontManager`）から等幅フォント名の一覧を返す関数。
   - 列挙結果の整形（重複除去・ソート・システム既定項目の付与）を純粋関数として切り出し、ユニットテスト可能にする。

3. **`ViewerBridge` 拡張（BefoldKit）**
   - 2つの CSS 変数注入スクリプトを追加:
     - `monoFontFamilyScript(_ family: String?) -> String`:
       `window._mmdMonoFontFamily = "<CSSで安全にエスケープした値>"`（nil のときは空 → JS 側でフォールバック）。
     - `codeFontSizeScript(_ points: Double) -> String`:
       `window._mmdCodeFontSize = <px>;`（pt→px 換算は既存 `viewer.js` の 13pt=16px 基準に合わせる）。
   - 生成スクリプト文字列をユニットテスト対象にする（エスケープ・数値整形）。

4. **`ViewerRenderer` / `viewer-main.js` 拡張**
   - `atDocumentStart` の初期注入に上記2スクリプトを追加し、`CodeFontPreference` の現在値を渡す。
   - JS 受け側で CSS 変数へ反映:
     - `--mmd-mono-font-family`: 空でなければ「`<選択フォント>, ` + 既存 monospace スタック」を組み立てて設定。
     - `--mmd-code-font-size`: px 値を設定。
   - ライブ更新: 既存のズーム再注入（`applyZoomScript` 相当）と同じ方式で、設定変更時に開いている全ウィンドウへ
     `evaluateJavaScript` で再注入する再適用スクリプトを1本追加する。

5. **CSS（style.css）変更**
   - `.code-body` の等幅適用箇所に `font-family: var(--mmd-mono-font-family, <既存スタック>);` を追加。
   - `.code-body pre code` のサイズを `font-size: var(--mmd-code-font-size, calc(var(--mmd-markdown-font-size, 16px) * 0.75));`
     とし、変数未設定時は従来挙動にフォールバック。
   - プレビュー内コード（`.markdown-body code`, `pre code`）には `font-family` 変数のみ適用し、**サイズは現状維持**。

6. **設定ウィンドウ（新規）**
   - `MainMenuBuilder` に「設定…」（Cmd+,）メニュー項目を追加。**ただし
     `FeatureGate.inProgressFeaturesEnabled` が true のときだけ項目を追加**する
     （stable ビルドでは項目そのものが出ない）。同ウィンドウを開く経路もゲートで囲う。
   - `CodeFontSettingsWindowController: NSWindowController` が `NSHostingController` 経由で
     SwiftUI の `CodeFontSettingsView` をホスト（`ViewerWindowController` と同じ AppKit+SwiftUI ホスティングパターン）。
   - `CodeFontSettingsView`: ファミリーのポップアップ（`MonospaceFontCatalog` 由来）+ サイズのステッパー/入力 +
     サンプルコードの小さなライブプレビュー。
   - シングルトン的に1枚だけ開く（既に開いていれば前面化）。

### データフロー

```
設定ウィンドウ操作
  → CodeFontPreference（UserDefaults 永続化, @Observable）
    → 変更通知 → 開いている各 ViewerRenderer へ再適用スクリプトを evaluateJavaScript
      → viewer-main.js が CSS 変数（--mmd-mono-font-family / --mmd-code-font-size）を更新
        → style.css が .code-body / プレビュー内コードに反映
```

新規ウィンドウ生成時は `atDocumentStart` の初期注入で同じ値を最初から適用する。

## エラー処理・エッジケース

- **選択フォントが後で消える/存在しない**: CSS の font-family は無効値を無視して次のフォールバックへ進むため、
  等幅スタックが自然に効く。特別なハンドリングは不要。
- **フォント名のエスケープ**: フォント名を JS/CSS に埋め込む際、引用符・バックスラッシュ・改行を安全にエスケープし、
  文字列注入の破綻や XSS 経路を作らない（既存の DOMPurify 方針と整合）。
- **サイズの異常値**: UI で 6〜32pt にクランプ。ストア読み込み時も範囲外は既定値へ丸める。
- **SPM 単体ビルド / バンドル外**: 既存の fallback と同様、設定が読めなくても既定値で動作する。
- **ライブ更新のタイミング**: レンダリング未完了のウィンドウでも、次回描画時に `atDocumentStart` 値が効くため破綻しない。

## フィーチャーゲートと検証

本機能は TASK-180 のフィーチャーゲート機構に依存し、その最初の実利用者を兼ねる。

**依存・順序**: 先に TASK-180（`AppVersion.isPrerelease` / `FeatureGate`）を実装する。
本機能の設定メニュー・ウィンドウの露出を `FeatureGate.inProgressFeaturesEnabled` で囲う。

**ゲートが実際に効くことの検証方針（「ユニット＋実 dev リリース」で担保）**:

- **ロジック（主エビデンス, ビルド不要）**: `FeatureGate` の判定を「バージョン文字列を引数で受け取る純粋関数」
  として実装し、決定表をユニットテスト:
  - `isPrerelease("1.4.10-dev.1") == true` / `isPrerelease("1.4.10") == false`
  - dev バージョン→ON、stable バージョン→OFF、DEBUG→ON。
- **配線（ON パス）**: 通常運用の dev リリース（`bump.sh dev` → `release.yml` が
  `MARKETING_VERSION="1.4.10-dev.N"` を注入）で dogfood し、設定メニュー・ウィンドウが**出る**ことを確認。
- **配線（OFF パス）**: 次回の stable リリース（`bump.sh patch/minor`）で、設定メニュー・ウィンドウが
  **出ない**ことを確認。
- Debug ビルドはゲート常時 ON（`#if DEBUG`）のため、OFF 状態の目視は stable リリースでのみ行う
  （手元での署名付き2ビルド比較や Debug 用オーバーライドは採用しない）。

## テスト方針

- `CodeFontPreference`: `UserDefaults` DI で読み書き・既定値・永続化・範囲クランプ（ユニット）。
- `MonospaceFontCatalog` の整形ロジック（重複除去・ソート・システム既定項目付与）を純粋関数としてユニットテスト。
- `ViewerBridge` の新スクリプト生成（フォント名エスケープ・pt→px 整形・nil 時の空文字）をユニットテスト。
- CSS 変数フォールバック挙動は、変数未設定時に従来値になることを既存のレンダリングテスト観点で確認。
- WebView への実描画、設定ウィンドウの GUI、フォントパネルの見た目はリリース前手動確認（規約どおり自動対象外）。

## 完了後の撤去・負債管理

- 機能自体（フォント設定）は恒久機能。CSS 変数のフォールバックは「設定未導入時の互換」を担保する仕様であり、
  削除しないこと（コメントで明示する）。
- 一方、**フィーチャーゲートで囲った部分は一時的な足場**。フォント設定を stable に載せると決めた時点で、
  `FeatureGate.inProgressFeaturesEnabled` による分岐を撤去してデフォルト有効化する。
  この撤去タスクを backlog に登録しておき（TASK-180 の運用ルールに従う）、ゲートが恒久分岐として残る負債を防ぐ。
