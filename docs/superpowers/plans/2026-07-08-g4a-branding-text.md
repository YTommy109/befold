# G4a: 著作権表記とAboutパネルのブランディング修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

<!-- constrained-by ../plans/2026-07-08-ui-ux-improvements-roadmap.md#g4-ブランディングデザイン優先度-中〜低まとめて対応可 -->

**Goal:** GitHub Pages のフッターに著作権表記(Tommy109)を追加し、About パネルの
"Degino Inc." 表記を "Tommy109"・リンク先を GitHub プロフィールに差し替える。

**Architecture:** 静的HTML(docs/index.html)の文言追加と、Swift側の
`NSAttributedString` 生成コードの文字列/URL差し替えのみ。ロジック変更は
ないため純粋関数の抽出やユニットテストは不要（既存の `InfoPlistTests.swift`
等と同様、テキスト内容のドリフト検知テストのみ追加する）。

**Tech Stack:** Swift 6, AppKit, 静的HTML

## Global Constraints

- GitHub プロフィール URL: `https://github.com/YTommy109`（ユーザー確認済み）
- コミットメッセージは Conventional Commits + 日本語

---

### Task 1: GitHub Pages のフッターに著作権表記を追加する

**Files:**
- Modify: `docs/index.html:180-184`

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: 現状のフッターを確認する**

```html
<footer>
  <p>
    <a href="https://github.com/YTommy109/befold">GitHub</a> · MIT License
  </p>
</footer>
```

- [ ] **Step 2: 著作権表記を追加する**

`docs/index.html:180-184` を以下に置き換える:

```html
<footer>
  <p>
    <a href="https://github.com/YTommy109/befold">GitHub</a> · MIT License · © 2026 Tommy109
  </p>
</footer>
```

- [ ] **Step 3: 手動で確認する（自動テスト対象外）**

ブラウザで `docs/index.html` を開き、フッターに
「GitHub · MIT License · © 2026 Tommy109」と表示されることを確認する。

- [ ] **Step 4: コミット**

```bash
git add docs/index.html
git commit -m "feat: GitHub Pagesのフッターに著作権表記を追加する"
```

---

### Task 2: About パネルの表記を Degino Inc. から Tommy109 に変更する

**Files:**
- Modify: `BefoldApp/befold/App/AppDelegate.swift:150-164`
- Test: `BefoldApp/befoldTests/AppDelegateAboutPanelTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: 現状の aboutPanelOptions を確認する**

```swift
private var aboutPanelOptions: [NSApplication.AboutPanelOptionKey: Any] {
    let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    let credits = NSMutableAttributedString()
    credits.append(NSAttributedString(
        string: "befold",
        attributes: [.link: URL(string: "https://ytommy109.github.io/befold/") as Any, .font: font]
    ))
    credits.append(NSAttributedString(string: "\nCopyright © 2026 ", attributes: [.font: font]))
    credits.append(NSAttributedString(
        string: "Degino Inc.",
        attributes: [.link: URL(string: "https://www.degino.com/") as Any, .font: font]
    ))
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return [.credits: credits]
}
```

- [ ] **Step 2: 失敗するテストを書く**

`BefoldApp/befoldTests/AppDelegateAboutPanelTests.swift` を新規作成する。
`AppDelegate` は `@MainActor` かつ `NSApplicationDelegate` の実インスタンス化に
`NSApplication.shared` の初期化を伴うため、直接インスタンス化はせず、
`AppDelegate.swift` のソーステキストを読み込んで文言・URLの存在を検証する
（`ViewerBridgeTests.swift` の `bridgeFunctionsExistInViewerHTML` と同じ
「ドリフト検知」パターン）。

```swift
// BefoldApp/befoldTests/AppDelegateAboutPanelTests.swift
import Foundation
import Testing

@Suite
struct AppDelegateAboutPanelTests {
    @Test("AboutパネルがTommy109表記とGitHubプロフィールリンクを含む")
    func aboutPanelUsesTommy109Branding() throws {
        let source = try String(contentsOf: appDelegateURL(), encoding: .utf8)

        #expect(source.contains("\"Tommy109\""))
        #expect(source.contains("https://github.com/YTommy109"))
        #expect(!source.contains("Degino Inc."))
        #expect(!source.contains("https://www.degino.com/"))
    }

    private func appDelegateURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldTests
            .deletingLastPathComponent() // BefoldApp
            .appendingPathComponent("befold/App/AppDelegate.swift")
    }
}
```

- [ ] **Step 3: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter AppDelegateAboutPanelTests`
Expected: FAIL（現状は "Degino Inc." のままのため）

- [ ] **Step 4: aboutPanelOptions を書き換える**

`BefoldApp/befold/App/AppDelegate.swift:150-164` を以下に置き換える:

```swift
    private var aboutPanelOptions: [NSApplication.AboutPanelOptionKey: Any] {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: "befold",
            attributes: [.link: URL(string: "https://ytommy109.github.io/befold/") as Any, .font: font]
        ))
        credits.append(NSAttributedString(string: "\nCopyright © 2026 ", attributes: [.font: font]))
        credits.append(NSAttributedString(
            string: "Tommy109",
            attributes: [.link: URL(string: "https://github.com/YTommy109") as Any, .font: font]
        ))
        credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
        return [.credits: credits]
    }
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `cd BefoldApp && swift test --filter AppDelegateAboutPanelTests`
Expected: PASS

- [ ] **Step 6: 全テストを実行する**

Run: `cd BefoldApp && swift test`
Expected: 全テスト PASS

- [ ] **Step 7: 手動で動作確認する（自動テスト対象外）**

befold アプリを起動し、メニュー「befold > About befold」を開き、
"Tommy109" と表示され、クリックすると GitHub プロフィール
(`https://github.com/YTommy109`) がブラウザで開くことを確認する。

- [ ] **Step 8: コミット**

```bash
git add BefoldApp/befold/App/AppDelegate.swift BefoldApp/befoldTests/AppDelegateAboutPanelTests.swift
git commit -m "feat: AboutパネルのDegino表記をTommy109に変更する"
```
