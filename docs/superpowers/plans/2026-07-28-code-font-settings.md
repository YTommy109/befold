# ソースコードビューのフォント設定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ソースコードビューの等幅フォント（ファミリー＋絶対 pt サイズ）を設定でき、設定 UI は dev/DEBUG ビルドでのみ露出する（フィーチャーゲートの最初の実利用者を兼ねる）。

**Architecture:** 純粋ロジック（バージョン判定・フォント列挙・スクリプト生成）を BefoldCLI/BefoldKit に置きユニットテストで固める。設定値は `HiddenFilesPreference` 型の `CodeFontPreference` に永続化。反映は既存の「Swift → CSS 変数注入（`ViewerBridge` → `viewer-main.js` → `style.css`）」パイプラインに CSS 変数2本を足し、ライブ更新は既存のズーム再注入（`WebViewCommandController`）と同じ経路で行う。設定 UI は AppKit の `NSWindowController` が SwiftUI ビューをホストする（ADR 0001 の方針）。

**Tech Stack:** Swift 6 / AppKit + SwiftUI / WKWebView / Swift Testing / XcodeGen。

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）。UI・設定ストアは `@MainActor`。
- テスト関数名は英語 camelCase、日本語説明は `@Test("…")` 表示名で付ける。
- ベンダリング済み JS/CSS（`mermaid.min.js` / `markdown-it.min.js` / `github-markdown.css` 等）は編集禁止。CSS 変更は `BefoldKit/Resources/style.css` のみ、JS 変更は自前の `viewer-main.js` のみ。
- ローカライズ文字列を足したら `/l10n-check` で en/ja の整合を確認する。
- 等幅フォントファミリーはソースビュー＋プレビュー内コード両方へ、サイズ（絶対 pt）はソースビューのみへ適用する。
- pt→px 換算は既存規約（13pt = 16px、`points * 16 / 13`）に合わせる。
- ビルド確認: `cd BefoldApp && swift build`。テスト: `swift test`（要 Xcode.app）。

---

## Part A — フィーチャーゲート（TASK-180）

### Task 1: AppVersion にプレリリース判定を追加

**Files:**
- Modify: `BefoldApp/BefoldCLI/AppVersion.swift`
- Test: `BefoldApp/befoldTests/AppVersionTests.swift`

**Interfaces:**
- Produces: `AppVersion.isPrerelease(_ version: String) -> Bool`、`AppVersion.isCurrentPrerelease: Bool`

- [ ] **Step 1: 失敗するテストを書く**（`AppVersionTests.swift` の末尾 `}` の直前に追加）

```swift
    // MARK: - プレリリース判定（フィーチャーゲート土台 / TASK-180）

    @Test("`-dev.N` を含むバージョンはプレリリースと判定する")
    func detectsDevPrerelease() {
        #expect(AppVersion.isPrerelease("1.4.10-dev.1") == true)
    }

    @Test("接尾辞のない通常バージョンはプレリリースではない")
    func stableVersionIsNotPrerelease() {
        #expect(AppVersion.isPrerelease("1.4.10") == false)
    }

    @Test("ハイフンを含む任意のプレリリース表記も true")
    func anyHyphenSuffixIsPrerelease() {
        #expect(AppVersion.isPrerelease("2.0.0-beta") == true)
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter AppVersionTests`
Expected: FAIL（`isPrerelease` 未定義でコンパイルエラー）

- [ ] **Step 3: 実装を追加**（`AppVersion.swift` の `fallback` 定数の直後に追加）

```swift
    /// バージョン文字列が SemVer のプレリリース（ハイフン接尾辞）かどうか。
    /// dev リリースは `release.yml` がタグ名 `v1.4.10-dev.N` から MARKETING_VERSION を
    /// 注入するため、実行時にこの接尾辞で dev ビルドを判別できる。
    public static func isPrerelease(_ version: String) -> Bool {
        version.contains("-")
    }

    /// 実行中ビルドの `current` がプレリリースか。
    public static var isCurrentPrerelease: Bool {
        isPrerelease(current)
    }
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter AppVersionTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/BefoldCLI/AppVersion.swift BefoldApp/befoldTests/AppVersionTests.swift
git commit -m "feat: task-180 AppVersion にプレリリース判定 isPrerelease を追加する"
```

---

### Task 2: FeatureGate を追加し dev/DEBUG でのみ有効化する

**Files:**
- Create: `BefoldApp/befold/App/FeatureGate.swift`
- Test: `BefoldApp/befoldTests/FeatureGateTests.swift`
- Modify: `.claude/CLAUDE.md`（フィーチャーゲートの運用と撤去ルールを追記）

**Interfaces:**
- Consumes: `AppVersion.isPrerelease(_:)`, `AppVersion.current`
- Produces: `FeatureGate.inProgressFeaturesEnabled(version:isDebugBuild:) -> Bool`（純粋）、`FeatureGate.inProgressFeaturesEnabled: Bool`（実行時判定）

- [ ] **Step 1: 失敗するテストを書く**

```swift
// FeatureGateTests.swift
@testable import befold
import Testing

/// 開発中機能のゲート判定（dev/DEBUG のみ ON）を検証する。
@Suite
struct FeatureGateTests {
    @Test("dev バージョンなら有効（DEBUG でなくても）")
    func enabledForDevVersion() {
        #expect(FeatureGate.inProgressFeaturesEnabled(version: "1.4.10-dev.1", isDebugBuild: false) == true)
    }

    @Test("stable バージョンかつ非 DEBUG なら無効")
    func disabledForStableRelease() {
        #expect(FeatureGate.inProgressFeaturesEnabled(version: "1.4.10", isDebugBuild: false) == false)
    }

    @Test("DEBUG ビルドなら stable バージョンでも有効")
    func enabledInDebugBuild() {
        #expect(FeatureGate.inProgressFeaturesEnabled(version: "1.4.10", isDebugBuild: true) == true)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter FeatureGateTests`
Expected: FAIL（`FeatureGate` 未定義）

- [ ] **Step 3: 実装を追加**

```swift
// FeatureGate.swift
import BefoldCLI

/// 開発中でまだ stable リリースに載せたくない機能の露出を一元管理する窓口。
/// dev リリース（バージョンがプレリリース）または DEBUG ビルドでのみ true。
/// stable 昇格時は該当機能の分岐を撤去してデフォルト有効化すること（撤去タスクを backlog 登録）。
enum FeatureGate {
    /// 実行中ビルドで開発中機能を露出してよいか。
    static var inProgressFeaturesEnabled: Bool {
        #if DEBUG
            inProgressFeaturesEnabled(version: AppVersion.current, isDebugBuild: true)
        #else
            inProgressFeaturesEnabled(version: AppVersion.current, isDebugBuild: false)
        #endif
    }

    /// テスト可能な純粋判定。
    static func inProgressFeaturesEnabled(version: String, isDebugBuild: Bool) -> Bool {
        isDebugBuild || AppVersion.isPrerelease(version)
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter FeatureGateTests`
Expected: PASS

- [ ] **Step 5: 運用ドキュメントを追記**（`.claude/CLAUDE.md` の末尾に節を追加）

```markdown
## フィーチャーゲート（開発中機能の dev 限定露出）

- 未完成機能は `FeatureGate.inProgressFeaturesEnabled` で囲い、dev/DEBUG ビルドでのみ露出する。
  判定は「バージョン文字列のプレリリース接尾辞（`-dev.N`）」由来で、`UpdateChannel`（ユーザー設定）は流用しない。
- フラグは一時的な足場。stable に載せると決めた時点で分岐を撤去しデフォルト有効化し、撤去タスクを backlog に登録する。
- 検証は「ロジックはユニットテスト、ON は dev リリースの dogfood、OFF は次回 stable リリース」で担保する。
```

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/befold/App/FeatureGate.swift BefoldApp/befoldTests/FeatureGateTests.swift .claude/CLAUDE.md
git commit -m "feat: task-180 dev/DEBUG 限定のフィーチャーゲート FeatureGate を追加する"
```

---

## Part B — フォント設定（TASK-181 として起票予定）

### Task 3: CodeFontPreference 永続化ストア

**Files:**
- Create: `BefoldApp/befold/App/CodeFontPreference.swift`
- Test: `BefoldApp/befoldTests/CodeFontPreferenceTests.swift`

**Interfaces:**
- Produces: `@MainActor final class CodeFontPreference`。プロパティ `fontFamily: String?`（nil = システム既定）、`fontSizePoints: Double`。`init(defaults: UserDefaults = .standard)`。定数 `CodeFontPreference.minPoints = 6`、`maxPoints = 32`、`defaultPoints = 10`。

- [ ] **Step 1: 失敗するテストを書く**

```swift
// CodeFontPreferenceTests.swift
@testable import befold
import Foundation
import Testing

@MainActor
@Suite
struct CodeFontPreferenceTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "CodeFontPreferenceTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("初期状態はファミリー nil・既定サイズ")
    func defaultsWhenUnset() {
        let pref = CodeFontPreference(defaults: makeDefaults())
        #expect(pref.fontFamily == nil)
        #expect(pref.fontSizePoints == CodeFontPreference.defaultPoints)
    }

    @Test("設定値が UserDefaults に永続化され再読込で復元される")
    func persistsAndRestores() {
        let defaults = makeDefaults()
        let pref = CodeFontPreference(defaults: defaults)
        pref.fontFamily = "SF Mono"
        pref.fontSizePoints = 13

        let reloaded = CodeFontPreference(defaults: defaults)
        #expect(reloaded.fontFamily == "SF Mono")
        #expect(reloaded.fontSizePoints == 13)
    }

    @Test("範囲外サイズは読み込み時に既定へ丸める")
    func clampsOutOfRangeSizeOnLoad() {
        let defaults = makeDefaults()
        defaults.set(999.0, forKey: "CodeFontSizePoints")
        let pref = CodeFontPreference(defaults: defaults)
        #expect(pref.fontSizePoints == CodeFontPreference.defaultPoints)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter CodeFontPreferenceTests`
Expected: FAIL（`CodeFontPreference` 未定義）

- [ ] **Step 3: 実装を追加**

```swift
// CodeFontPreference.swift
import Foundation

/// ソースコードビューの等幅フォント設定（ファミリー・サイズ）を UserDefaults に永続化する。
/// HiddenFilesPreference と同じ「注入して全ウィンドウで共有する」パターン。
@MainActor
final class CodeFontPreference {
    static let minPoints: Double = 6
    static let maxPoints: Double = 32
    /// 既定サイズ。現状の見た目（本文16px × 0.75 = 12px）に近い値。
    static let defaultPoints: Double = 10

    private let defaults: UserDefaults
    private static let familyKey = "CodeFontFamily"
    private static let sizeKey = "CodeFontSizePoints"

    /// nil はシステム既定（ハードコード等幅スタックへフォールバック）。
    var fontFamily: String? {
        didSet { defaults.set(fontFamily, forKey: Self.familyKey) }
    }

    var fontSizePoints: Double {
        didSet {
            fontSizePoints = Self.clamp(fontSizePoints)
            defaults.set(fontSizePoints, forKey: Self.sizeKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontFamily = defaults.string(forKey: Self.familyKey)
        let stored = defaults.object(forKey: Self.sizeKey) as? Double
        fontSizePoints = stored.map(Self.clamp) ?? Self.defaultPoints
    }

    private static func clamp(_ points: Double) -> Double {
        guard points >= minPoints, points <= maxPoints else { return defaultPoints }
        return points
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter CodeFontPreferenceTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/CodeFontPreference.swift BefoldApp/befoldTests/CodeFontPreferenceTests.swift
git commit -m "feat: ソースコードフォント設定の永続化ストア CodeFontPreference を追加する"
```

---

### Task 4: MonospaceFontCatalog（等幅フォント列挙）

**Files:**
- Create: `BefoldApp/befold/App/MonospaceFontCatalog.swift`
- Test: `BefoldApp/befoldTests/MonospaceFontCatalogTests.swift`

**Interfaces:**
- Produces: `enum MonospaceFontCatalog`。`static func names(from rawFamilyNames: [String]) -> [String]`（整形：重複除去・ソート）と `static func systemMonospaceFamilyNames() -> [String]`（`NSFontManager` 由来、GUI 用）。

- [ ] **Step 1: 失敗するテストを書く**

```swift
// MonospaceFontCatalogTests.swift
@testable import befold
import Testing

@Suite
struct MonospaceFontCatalogTests {
    @Test("重複を除きアルファベット順に整列する")
    func dedupesAndSorts() {
        let result = MonospaceFontCatalog.names(from: ["Menlo", "SF Mono", "Menlo"])
        #expect(result == ["Menlo", "SF Mono"])
    }

    @Test("空入力は空を返す")
    func emptyInput() {
        #expect(MonospaceFontCatalog.names(from: []).isEmpty)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter MonospaceFontCatalogTests`
Expected: FAIL

- [ ] **Step 3: 実装を追加**

```swift
// MonospaceFontCatalog.swift
import AppKit

/// システムの等幅フォント名一覧を提供する。整形（重複除去・ソート）は純粋関数として切り出す。
enum MonospaceFontCatalog {
    /// 整形のみ（テスト対象）。
    static func names(from rawFamilyNames: [String]) -> [String] {
        Array(Set(rawFamilyNames)).sorted()
    }

    /// システムから等幅フォントファミリー名を集める（GUI 用、テスト対象外）。
    @MainActor
    static func systemMonospaceFamilyNames() -> [String] {
        let manager = NSFontManager.shared
        let raw = manager.availableFontFamilies.filter { family in
            guard let members = manager.availableMembers(ofFontFamily: family) else { return false }
            // メンバのいずれかが固定幅トレイトを持てば等幅ファミリーとみなす。
            return members.contains { member in
                guard member.count >= 4, let traits = member[3] as? UInt else { return false }
                return NSFontTraitMask(rawValue: traits).contains(.fixedPitchFontMask)
            }
        }
        return names(from: raw)
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter MonospaceFontCatalogTests`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/MonospaceFontCatalog.swift BefoldApp/befoldTests/MonospaceFontCatalogTests.swift
git commit -m "feat: 等幅フォント列挙 MonospaceFontCatalog を追加する"
```

---

### Task 5: ViewerBridge に等幅フォント注入スクリプトを追加

**Files:**
- Modify: `BefoldApp/BefoldKit/ViewerBridge.swift`（`systemFontSizeScript` の直後、63行付近）
- Test: `BefoldApp/befoldTests/ViewerBridgeTests.swift`

**Interfaces:**
- Consumes: `PlainFunction.initCodeFont`（Task 6 で JS 側に用意する呼び出し。`ViewerBridge` 内の `PlainFunction` enum に case を追加）
- Produces:
  - `ViewerBridge.monoFontFamilyScript(_ family: String?) -> String` → `window._mmdMonoFontFamily = "<escaped>";`（nil は空文字）
  - `ViewerBridge.codeFontSizeScript(_ points: Double) -> String` → `window._mmdCodeFontSize = <points>;`
  - `ViewerBridge.applyCodeFontScript(family:points:) -> String`（上2つ＋ `initCodeFont` 呼び出し）

- [ ] **Step 1: 失敗するテストを書く**（`ViewerBridgeTests.swift` に追加）

```swift
    @Test("フォントファミリーは JSON エスケープして注入する")
    func monoFontFamilyEscapes() {
        #expect(ViewerBridge.monoFontFamilyScript("SF Mono") == "window._mmdMonoFontFamily = \"SF Mono\";")
    }

    @Test("ファミリー nil のときは空文字を注入する")
    func monoFontFamilyNilIsEmpty() {
        #expect(ViewerBridge.monoFontFamilyScript(nil) == "window._mmdMonoFontFamily = \"\";")
    }

    @Test("引用符を含むフォント名でも壊れない（エスケープされる）")
    func monoFontFamilyWithQuote() {
        #expect(ViewerBridge.monoFontFamilyScript("a\"b") == "window._mmdMonoFontFamily = \"a\\\"b\";")
    }

    @Test("コードフォントサイズを pt 値として注入する")
    func codeFontSizeScriptEmitsPoints() {
        #expect(ViewerBridge.codeFontSizeScript(11) == "window._mmdCodeFontSize = 11.0;")
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter ViewerBridgeTests`
Expected: FAIL

- [ ] **Step 3: 実装を追加**（`systemFontSizeScript` の直後）

```swift
    /// 等幅フォントファミリーを注入する。ソースビュー＋プレビュー内コード両方に適用される。
    /// JSON エンコードで JS インジェクションを防ぐ。nil/失敗時は空文字（JS 側でフォールバック）。
    public static func monoFontFamilyScript(_ family: String?) -> String {
        let json = (try? String(data: JSONEncoder().encode(family ?? ""), encoding: .utf8)) ?? "\"\""
        return "window._mmdMonoFontFamily = \(json ?? "\"\"");"
    }

    /// コードビューの絶対フォントサイズ（pt）を注入する。ソースビューのみに適用される。
    public static func codeFontSizeScript(_ points: Double) -> String {
        "window._mmdCodeFontSize = \(points);"
    }

    /// 設定変更時にファミリーとサイズを注入し直して即時反映するスクリプト。
    public static func applyCodeFontScript(family: String?, points: Double) -> String {
        monoFontFamilyScript(family) + " " + codeFontSizeScript(points)
            + " \(PlainFunction.initCodeFont.callScript);"
    }
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter ViewerBridgeTests`
Expected: PASS（`PlainFunction.initCodeFont` は Task 6 で追加。本 Task では `applyCodeFontScript` を使うテストを書かないため未定義参照を避ける。Step 3 の `applyCodeFontScript` は Task 6 完了までコンパイルを通すため、`PlainFunction` への case 追加を本 Step に含める。）

- [ ] **Step 5: `PlainFunction` に case を追加**（`ViewerBridge.swift` 内の `enum PlainFunction` の定義へ、`initZoom` に倣って）

```swift
    case initCodeFont
    // callScript 実装（既存パターンに合わせる）: "_mmdInitCodeFont()"
```

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/BefoldKit/ViewerBridge.swift BefoldApp/befoldTests/ViewerBridgeTests.swift
git commit -m "feat: ViewerBridge に等幅フォント/コードサイズ注入スクリプトを追加する"
```

---

### Task 6: viewer-main.js に CSS 変数反映を追加

**Files:**
- Modify: `BefoldApp/BefoldKit/Resources/viewer-main.js`（`_mmdInitFontSize` の直後 85行付近、および 1530・1541 行のエクスポート／初期化）

**Interfaces:**
- Consumes: `window._mmdMonoFontFamily`（文字列）、`window._mmdCodeFontSize`（pt 数値）
- Produces: グローバル `_mmdInitCodeFont`（`ViewerBridge.PlainFunction.initCodeFont.callScript` が呼ぶ）

- [ ] **Step 1: 反映関数を追加**（`_mmdInitFontSize` 関数の直後）

```javascript
  // Swift が注入した等幅フォント設定を CSS 変数へ反映する。
  //  --mmd-mono-font-family: ソースビュー＋プレビュー内コード両方（ファミリーのみ）
  //  --mmd-code-font-size:   ソースビューのみ（絶対サイズ、px）
  function _mmdInitCodeFont() {
    var root = document.documentElement;
    var family = window._mmdMonoFontFamily || '';
    if (family) {
      // 選択フォントを先頭に、既存の monospace スタックをフォールバックとして連結。
      root.style.setProperty('--mmd-mono-font-family',
        '"' + family + '", ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace');
    } else {
      root.style.removeProperty('--mmd-mono-font-family');
    }
    var pt = window._mmdCodeFontSize;
    if (typeof pt === 'number' && pt > 0) {
      // 既存規約（13pt = 16px）に合わせて px 換算。
      root.style.setProperty('--mmd-code-font-size', (pt * 16 / 13) + 'px');
    } else {
      root.style.removeProperty('--mmd-code-font-size');
    }
  }
```

- [ ] **Step 2: 初期化呼び出しに追加**（1530行 `_mmdInitFontSize();` の直後）

```javascript
    _mmdInitCodeFont();
```

- [ ] **Step 3: エクスポートに追加**（1541行 `_mmdInitFontSize: _mmdInitFontSize,` の直後）

```javascript
      _mmdInitCodeFont: _mmdInitCodeFont,
```

- [ ] **Step 4: ビルドが通ることを確認**

Run: `cd BefoldApp && swift build`
Expected: Build complete（JS はリソースのため構文はビルドでは検査されない。Task 10 の手動確認で描画を検証する）

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/BefoldKit/Resources/viewer-main.js
git commit -m "feat: viewer-main.js に等幅フォント CSS 変数の反映を追加する"
```

---

### Task 7: style.css に CSS 変数を適用

**Files:**
- Modify: `BefoldApp/BefoldKit/Resources/style.css`（193-198行のプレビューコード、242-254行の `.code-body pre code`）

- [ ] **Step 1: プレビュー内コードにファミリー変数を適用**（193-198 の `font-size: 0.75em;` ブロックへ `font-family` を追記。サイズは変えない）

```css
#diagram-wrap.markdown-body tt,
#diagram-wrap.markdown-body code,
#diagram-wrap.markdown-body samp,
#diagram-wrap.markdown-body pre {
  font-size: 0.75em;
  /* 未設定時はベンダー CSS の monospace スタックにフォールバック（削除しないこと） */
  font-family: var(--mmd-mono-font-family, inherit);
}
```

- [ ] **Step 2: ソースビューにファミリー＋サイズ変数を適用**（242-254 の `#diagram-wrap.code-body pre code` の `font-size` を差し替え、`font-family` を追記）

```css
#diagram-wrap.code-body pre code {
  display: block;
  height: 100%;
  overflow: auto;
  padding: 0.25em 0.5ch;
  /* 未設定時は従来挙動（本文 × 0.75）にフォールバック（削除しないこと） */
  font-size: var(--mmd-code-font-size, calc(var(--mmd-markdown-font-size, 16px) * 0.75));
  font-family: var(--mmd-mono-font-family, inherit);
  line-height: 1.45;
  white-space: pre-wrap;
  word-break: break-all;
  tab-size: 4;
  -moz-tab-size: 4;
}
```

- [ ] **Step 3: ビルドが通ることを確認**

Run: `cd BefoldApp && swift build`
Expected: Build complete

- [ ] **Step 4: コミット**

```bash
git add BefoldApp/BefoldKit/Resources/style.css
git commit -m "feat: style.css の等幅フォントを CSS 変数で差し替え可能にする"
```

---

### Task 8: レンダラの初期注入に設定値を差し込む

**Files:**
- Modify: `BefoldApp/BefoldRenderKit/ViewerRenderer.swift`（128-146行 `userScriptSources`）
- Modify: `ViewerRenderer` の設定メソッド（`initialZoom` 等を受け取っている構成経路）と、その呼び出し元 `BefoldApp/befold/App/ViewerWindowController.swift`
- Test: `BefoldApp/befoldTests/ViewerRendererOneShotTests.swift` または既存の注入検証テストに追記

**Interfaces:**
- Consumes: `CodeFontPreference`（`fontFamily`, `fontSizePoints`）、`ViewerBridge.monoFontFamilyScript`, `ViewerBridge.codeFontSizeScript`
- Produces: 初期ロード時に `--mmd-mono-font-family` / `--mmd-code-font-size` が反映される

- [ ] **Step 1: `userScriptSources` に2行追加**（`systemFontSizeScript(...)` の直後）

```swift
            ViewerBridge.monoFontFamilyScript(codeFontFamily),
            ViewerBridge.codeFontSizeScript(codeFontSizePoints),
```

- [ ] **Step 2: 構成経路にパラメータを追加**

`ViewerRenderer` の設定メソッドに `codeFontFamily: String?` と `codeFontSizePoints: Double` を追加し、`ViewerWindowController` は共有 `CodeFontPreference`（Task 9 で注入）から `pref.fontFamily` / `pref.fontSizePoints` を渡す。既定注入テスト（`ViewerRendererOneShotTests` 系）で「注入スクリプト列に `_mmdMonoFontFamily` と `_mmdCodeFontSize` が含まれる」ことを assert する1ケースを追加。

- [ ] **Step 3: テスト・ビルドを実行**

Run: `cd BefoldApp && swift build && swift test --filter ViewerRenderer`
Expected: PASS

- [ ] **Step 4: コミット**

```bash
git add BefoldApp/BefoldRenderKit/ViewerRenderer.swift BefoldApp/befold/App/ViewerWindowController.swift BefoldApp/befoldTests/
git commit -m "feat: ソースビューのフォント設定を初回描画時に注入する"
```

---

### Task 9: 共有 CodeFontPreference の配線とライブ更新

**Files:**
- Modify: `BefoldApp/befold/App/AppDelegate.swift`（44行付近で `CodeFontPreference` を生成・所有）
- Modify: `BefoldApp/befold/App/ViewerWindowManager.swift`（`hiddenFilesPreference` と同様に注入・保持し、全 `ViewerWindowController` へ渡す）
- Modify: `BefoldApp/befold/App/WebViewCommandController.swift`（`applyZoom` に倣った `applyCodeFont()` を追加）

**Interfaces:**
- Consumes: `ViewerBridge.applyCodeFontScript(family:points:)`
- Produces: `WebViewCommandController.applyCodeFont(family:points:)`（開いている各 WebView へ再注入）、`ViewerWindowManager.applyCodeFontToAllWindows()`

- [ ] **Step 1: 共有インスタンスを生成・注入**

`AppDelegate` で `let codeFontPreference = CodeFontPreference()` を持ち、`ViewerWindowManager(... codeFontPreference: codeFontPreference)` として渡す（`hiddenFilesPreference` と同じ DI パターン、`ViewerWindowManager.swift:56` に倣う）。`ViewerWindowManager.openViewer`（182行付近）で各 `ViewerWindowController` に渡す。

- [ ] **Step 2: ライブ再注入メソッドを追加**（`WebViewCommandController.swift`、44行の `applyZoom` に倣う）

```swift
    /// 設定変更時に等幅フォント設定を注入し直して即時反映する。
    func applyCodeFont(family: String?, points: Double) {
        evaluate(ViewerBridge.applyCodeFontScript(family: family, points: points))
    }
```

- [ ] **Step 3: 設定変更を全ウィンドウへ伝播**

`ViewerWindowManager` に `applyCodeFontToAllWindows()` を追加し、保持する各 `ViewerWindowController`（`controllers` 辞書の値）の `WebViewCommandController.applyCodeFont(...)` を呼ぶ。Task 10 の設定ビューがこれを設定変更時に呼ぶ。

- [ ] **Step 4: ビルドを実行**

Run: `cd BefoldApp && swift build`
Expected: Build complete

- [ ] **Step 5: コミット**

```bash
git add BefoldApp/befold/App/AppDelegate.swift BefoldApp/befold/App/ViewerWindowManager.swift BefoldApp/befold/App/WebViewCommandController.swift
git commit -m "feat: CodeFontPreference を全ウィンドウ共有しライブ更新できるようにする"
```

---

### Task 10: 設定ウィンドウ・メニュー（フィーチャーゲート付き, 手動確認）

**Files:**
- Create: `BefoldApp/befold/App/CodeFontSettingsWindowController.swift`
- Create: `BefoldApp/befold/Viewer/CodeFontSettingsView.swift`
- Modify: `BefoldApp/befold/App/MainMenuBuilder.swift`（App メニュー、44行の最初の separator 前に「設定…」を追加）
- Modify: `BefoldApp/befold/App/AppDelegate.swift`（`@objc func showSettings(_:)` と controller 保持）
- Modify: ローカライズ（`menu.app.settings`、設定ビューのラベル各種）

**Interfaces:**
- Consumes: `FeatureGate.inProgressFeaturesEnabled`, `CodeFontPreference`, `MonospaceFontCatalog.systemMonospaceFamilyNames()`, `ViewerWindowManager.applyCodeFontToAllWindows()`

- [ ] **Step 1: メニュー項目をゲート付きで追加**（`makeAppMenuItem` 内、`checkForUpdates` の後・`installCLI` の前あたり）

```swift
        if FeatureGate.inProgressFeaturesEnabled {
            let settings = menu.addItem(
                withTitle: String(localized: "menu.app.settings", bundle: .l10n),
                action: #selector(AppDelegate.showSettings(_:)),
                keyEquivalent: ","
            )
            settings.keyEquivalentModifierMask = [.command]
        }
```

- [ ] **Step 2: 設定ビューを実装**（`CodeFontSettingsView.swift`）

`@Bindable var preference: CodeFontPreference` を受け、ファミリーの `Picker`（先頭に「システム既定」＝ nil、以降 `MonospaceFontCatalog.systemMonospaceFamilyNames()`）、サイズの `Stepper`/`TextField`（`CodeFontPreference.minPoints...maxPoints`）、サンプルコードのプレビュー `Text` を等幅で表示。値変更時に `onChange` で `ViewerWindowManager.applyCodeFontToAllWindows()` を呼ぶクロージャを受け取る。

- [ ] **Step 3: ウィンドウコントローラを実装**（`CodeFontSettingsWindowController.swift`）

`NSWindowController` が `NSHostingController(rootView: CodeFontSettingsView(...))` を `contentViewController` にする（`ViewerSplitViewController.swift:26` の `NSHostingController` 利用に倣う）。既に開いていれば前面化する単一インスタンス。

- [ ] **Step 4: AppDelegate に開くアクションを追加**

```swift
    @objc func showSettings(_ sender: Any?) {
        codeFontSettingsWindowController.showWindow(sender)
        codeFontSettingsWindowController.window?.makeKeyAndOrderFront(sender)
    }
```

- [ ] **Step 5: ローカライズ確認**

Run: `/l10n-check`
Expected: `menu.app.settings` ほか追加キーの en/ja が揃っている

- [ ] **Step 6: 手動確認（GUI, 規約により自動テスト対象外）**

```bash
cd BefoldApp && swift build
# DEBUG 実行では FeatureGate が常時 ON。設定メニュー(Cmd+,)→ ファミリー/サイズ変更 →
# 開いているソースファイル表示が即時にフォント・サイズ変更されること、
# プレビュー内コードはファミリーのみ連動しサイズは不変であることを目視確認。
```

- [ ] **Step 7: コミット**

```bash
git add BefoldApp/befold/App/CodeFontSettingsWindowController.swift BefoldApp/befold/Viewer/CodeFontSettingsView.swift BefoldApp/befold/App/MainMenuBuilder.swift BefoldApp/befold/App/AppDelegate.swift BefoldApp/befold/Resources/
git commit -m "feat: 等幅フォント設定ウィンドウを追加する（フィーチャーゲート付き）"
```

---

### Task 11: project.yml へのファイル反映と全体テスト

**Files:**
- Modify: `BefoldApp/project.yml`（新規ファイルがターゲットに含まれるか確認。ソースはディレクトリ一括指定なら不要な場合あり）

- [ ] **Step 1: XcodeGen 再生成（必要時）**

Run: `cd BefoldApp && xcodegen generate`
Expected: エラーなし（`.xcodeproj` 更新）

- [ ] **Step 2: 全テスト実行**

Run: `cd BefoldApp && swift build && swift test`
Expected: 全 PASS

- [ ] **Step 3: コミット（差分があれば）**

```bash
git add BefoldApp/project.yml BefoldApp/befold.xcodeproj
git commit -m "chore: フォント設定の新規ファイルをプロジェクトへ反映する"
```

---

## 起票フォローアップ（実装外）

- 本 Part B の作業に対応する backlog タスク（TASK-181 相当「ソースコードビューのフォント設定を実装する」）を、実装着手前に task-creation ガイドに従って起票する（TASK-179/180 と同じ運用）。
- フォント設定を stable に載せると決めた時点で、Task 2/Task 10 で入れた `FeatureGate` 分岐を撤去する backlog タスクを登録する（TASK-180 の運用ルール）。

## Self-Review メモ

- スペック網羅: 対象2項目（ファミリー/サイズ）、適用先分離（ファミリー=両方 / サイズ=ソースのみ）、グローバル設定、ライブ更新、ズーム非干渉、ゲート露出、検証方針、撤去運用 — すべて Task 1〜11 に割り付け済み。
- 型整合: `CodeFontPreference.fontFamily: String?` / `fontSizePoints: Double`、`ViewerBridge.monoFontFamilyScript`/`codeFontSizeScript`/`applyCodeFontScript`、JS `_mmdMonoFontFamily`/`_mmdCodeFontSize`/`_mmdInitCodeFont`、CSS `--mmd-mono-font-family`/`--mmd-code-font-size` — Task 間で名称一致を確認済み。
- 未確定の実装詳細（要実装時確認）: `ViewerRenderer` の設定メソッド正確なシグネチャ（Task 8 Step 2）、`ViewerBridge.PlainFunction` の `callScript` 実装様式（Task 5 Step 5）、`project.yml` のソース指定方式（Task 11）。いずれも既存の同種コードに倣う。
