# CLI Command Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a menu item that installs a `befold` shim command into `/usr/local/bin`, so `befold <file>` opens a file and `befold <directory>` opens the first supported file in that directory (VSCode-style CLI install).

**Architecture:** A pure, testable `CLIInstaller` generates the shim script and writes it to the target path (falling back to an AppleScript administrator-privileges prompt on permission failure). `DirectoryLister` gains a small pure resolver that turns a directory URL into the first supported file inside it, reusing the existing (already tested) `firstSupportedFile(in:)`. `AppDelegate` wires both into a new App-menu item and the existing `openViewer(for:)` entry point.

**Tech Stack:** Swift 6, AppKit, Swift Testing (`befoldTests/`), XcodeGen project (`BefoldApp/project.yml` — no target changes needed).

## Global Constraints

- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`) — all new types touching AppKit/`NSApp` must be `@MainActor`.
- Test function names must be English camelCase; use `@Test("日本語の説明")` for the display name (SwiftLint `identifier_name` rejects non-ASCII-leading identifiers).
- Follow Conventional Commits + Japanese commit messages (e.g. `feat: PATH に befold コマンドをインストールする機能を追加する`).
- Menu strings go through `Localizable.xcstrings` and are read via `String(localized:bundle: .l10n)` — never hardcode UI strings.
- No new CLI executable target — the shim is a plain shell script written to disk at install time, not a compiled binary.

---

### Task 1: Directory-to-file resolution in `DirectoryLister`

**Files:**
- Modify: `BefoldApp/befold/Viewer/DirectoryLister.swift`
- Test: `BefoldApp/befoldTests/DirectoryListerTests.swift`

**Interfaces:**
- Consumes: existing `DirectoryLister.firstSupportedFile(in: URL) -> URL?` (already defined at `DirectoryLister.swift:74`).
- Produces: `DirectoryLister.resolveFileToOpen(at: URL) -> URL?` — used by Task 2 (`AppDelegate.openViewer(for:)`).
  - If `url` is an existing directory: returns `firstSupportedFile(in: url)` (nil if none found).
  - Otherwise (file, or path that doesn't exist): returns `url` unchanged, so existing behavior for files/missing paths is untouched.

- [ ] **Step 1: Write the failing tests**

Append to `BefoldApp/befoldTests/DirectoryListerTests.swift` (inside the `DirectoryListerTests` struct, after the last existing test):

```swift
    @Test("resolveFileToOpen はディレクトリを渡すと最初の対応ファイルを返す")
    func resolveFileToOpenReturnsFirstSupportedFileForDirectory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "b.mmd", contents: "graph TD;")
        _ = try tmp.file(named: "a.mmd", contents: "graph TD;")

        let result = DirectoryLister.resolveFileToOpen(at: tmp.url)

        #expect(result?.lastPathComponent == "a.mmd")
    }

    @Test("resolveFileToOpen は対応ファイルのないディレクトリで nil を返す")
    func resolveFileToOpenReturnsNilForEmptyDirectory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "unsupported.xyz", contents: "skip me")

        let result = DirectoryLister.resolveFileToOpen(at: tmp.url)

        #expect(result == nil)
    }

    @Test("resolveFileToOpen はファイルパスをそのまま返す")
    func resolveFileToOpenReturnsFileUnchanged() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")

        let result = DirectoryLister.resolveFileToOpen(at: file)

        #expect(result == file)
    }

    @Test("resolveFileToOpen は存在しないパスをそのまま返す")
    func resolveFileToOpenReturnsMissingPathUnchanged() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")

        let result = DirectoryLister.resolveFileToOpen(at: missing)

        #expect(result == missing)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd BefoldApp && swift test --filter DirectoryListerTests`
Expected: FAIL with "value of type 'DirectoryLister.Type' has no member 'resolveFileToOpen'"

- [ ] **Step 3: Implement `resolveFileToOpen`**

Add to `BefoldApp/befold/Viewer/DirectoryLister.swift`, inside the `DirectoryLister` enum, after `firstSupportedFile(in:)`:

```swift
    /// CLI シム経由のオープン用にパスを解決する。
    /// ディレクトリならフォルダー内最初の対応ファイルを返し(見つからなければ nil)、
    /// ファイル・存在しないパスはそのまま返す(既存のオープン/エラー表示フローに委譲する)。
    static func resolveFileToOpen(at url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            return url
        }
        return firstSupportedFile(in: url)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd BefoldApp && swift test --filter DirectoryListerTests`
Expected: PASS (all `DirectoryListerTests`, including the 4 new tests)

- [ ] **Step 5: Commit**

```bash
cd BefoldApp
git add befold/Viewer/DirectoryLister.swift befoldTests/DirectoryListerTests.swift
git commit -m "feat: ディレクトリを最初の対応ファイルに解決する DirectoryLister.resolveFileToOpen を追加する"
```

---

### Task 2: Wire directory resolution into `AppDelegate.openViewer(for:)`

**Files:**
- Modify: `BefoldApp/befold/App/AppDelegate.swift:109-112`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `DirectoryLister.resolveFileToOpen(at:) -> URL?` (Task 1).
- Produces: `AppDelegate.openViewer(for: URL)` now handles directories transparently — no change to its public signature, so all existing call sites (`DocumentController`, `application(_:open:)`, Recent Documents, `showOpenPanel`) keep working unchanged.

This task has no unit-testable surface of its own (the branching logic it calls is already covered by Task 1's tests; `AppDelegate` itself is a `@MainActor` singleton driving `NSApplication`, consistent with how `checkForUpdates`/`showAbout` are also left untested and verified manually). Verification is manual, done at the end of Task 4.

- [ ] **Step 1: Add the new localization key**

In `BefoldApp/befold/Resources/Localizable.xcstrings`, insert after the `"sidebar.context.revealInFinder"` entry (the last one in the file, ending at line 409), replacing:

```
    "sidebar.context.revealInFinder" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Reveal in Finder" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "Finder で開く" } }
      }
    }
  },
```

with:

```
    "sidebar.context.revealInFinder" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Reveal in Finder" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "Finder で開く" } }
      }
    },
    "cli.folder.noSupportedFile" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "No supported file found in this folder." } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "このフォルダーに対応ファイルが見つかりません。" } }
      }
    }
  },
```

- [ ] **Step 2: Update `openViewer(for:)`**

In `BefoldApp/befold/App/AppDelegate.swift`, replace (lines 109-112):

```swift
    /// 指定 URL のファイルをビューアウィンドウで開く(DocumentController・Recent メニューからも呼ばれる)。
    func openViewer(for url: URL) {
        windowManager.openViewer(for: url)
    }
```

with:

```swift
    /// 指定 URL のファイルをビューアウィンドウで開く(DocumentController・Recent メニューからも呼ばれる)。
    /// ディレクトリが渡された場合は、フォルダー内最初の対応ファイルを開く(CLI シム経由の想定)。
    func openViewer(for url: URL) {
        guard let target = DirectoryLister.resolveFileToOpen(at: url) else {
            presentNoSupportedFileAlert()
            return
        }
        windowManager.openViewer(for: target)
    }

    private func presentNoSupportedFileAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "cli.folder.noSupportedFile", bundle: .l10n)
        alert.runModal()
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd BefoldApp && swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
cd BefoldApp
git add befold/App/AppDelegate.swift befold/Resources/Localizable.xcstrings
git commit -m "feat: openViewer でディレクトリを開けるようにする"
```

---

### Task 3: `CLIInstaller` — shim script generation and install logic

**Files:**
- Create: `BefoldApp/befold/App/CLIInstaller.swift`
- Test: `BefoldApp/befoldTests/CLIInstallerTests.swift`

**Interfaces:**
- Produces:
  - `CLIInstaller.shimScriptContents(bundlePath: String) -> String`
  - `CLIInstaller.install(bundlePath: String, installPath: URL) -> Result<Void, CLIInstallError>`
  - `enum CLIInstallError: Error, Equatable { case writeFailed(String) }`
- Used by Task 4 (`AppDelegate.installCLI(_:)`), which will pass `installPath: URL(fileURLWithPath: "/usr/local/bin/befold")`.

- [ ] **Step 1: Write the failing tests**

Create `BefoldApp/befoldTests/CLIInstallerTests.swift`:

```swift
@testable import befold
import Foundation
import Testing

@Suite
struct CLIInstallerTests {
    @Test("シムスクリプトは指定の bundle path を open -a で呼び出す")
    func shimScriptContentsEmbedsBundlePath() {
        let script = CLIInstaller.shimScriptContents(bundlePath: "/Applications/befold.app")

        #expect(script.contains("#!/bin/bash"))
        #expect(script.contains(#"open -a "/Applications/befold.app" "$@""#))
    }

    @Test("書き込み可能な場所には直接インストールされる")
    func installWritesShimDirectlyWhenWritable() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")

        let result = CLIInstaller.install(bundlePath: "/Applications/befold.app", installPath: installPath)

        guard case .success = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        let contents = try String(contentsOf: installPath, encoding: .utf8)
        #expect(contents.contains("/Applications/befold.app"))
        let attributes = try FileManager.default.attributesOfItem(atPath: installPath.path)
        let permissions = attributes[.posixPermissions] as? Int
        #expect(permissions == 0o755)
    }

}
```

管理者権限フォールバック（`writeWithAdministratorPrivileges`）は実行すると実際に OS のパスワードプロンプトを
表示してしまうため、ユニットテストの対象にしない。Task 5 の手動確認でカバーする。

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd BefoldApp && swift test --filter CLIInstallerTests`
Expected: FAIL with "cannot find 'CLIInstaller' in scope"

- [ ] **Step 3: Implement `CLIInstaller`**

Create `BefoldApp/befold/App/CLIInstaller.swift`:

```swift
import AppKit
import Foundation

enum CLIInstallError: Error, Equatable {
    case writeFailed(String)
}

/// PATH に `befold` コマンドをインストールする(VSCode の `code` コマンド相当)。
enum CLIInstaller {
    /// `open -a` 経由でアプリを起動するシムスクリプトの内容を生成する。
    static func shimScriptContents(bundlePath: String) -> String {
        """
        #!/bin/bash
        exec open -a "\(bundlePath)" "$@"

        """
    }

    /// `installPath` にシムスクリプトを書き込む。書き込み権限がない場合は
    /// 管理者権限(AppleScript `with administrator privileges`)での書き込みにフォールバックする。
    static func install(bundlePath: String, installPath: URL) -> Result<Void, CLIInstallError> {
        let contents = shimScriptContents(bundlePath: bundlePath)
        if writeDirectly(contents: contents, to: installPath) {
            return .success(())
        }
        if writeWithAdministratorPrivileges(contents: contents, to: installPath) {
            return .success(())
        }
        return .failure(.writeFailed(installPath.path))
    }

    private static func writeDirectly(contents: String, to url: URL) -> Bool {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private static func writeWithAdministratorPrivileges(contents: String, to url: URL) -> Bool {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try contents.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let destPath = url.path
        let dirPath = url.deletingLastPathComponent().path
        let script = """
        do shell script "mkdir -p \\"\(dirPath)\\" && cp \\"\(tempURL.path)\\" \\"\(destPath)\\" && chmod 755 \\"\(destPath)\\"" with administrator privileges
        """
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)
        return errorDict == nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd BefoldApp && swift test --filter CLIInstallerTests`
Expected: PASS (all 3 tests)

- [ ] **Step 5: Commit**

```bash
cd BefoldApp
git add befold/App/CLIInstaller.swift befoldTests/CLIInstallerTests.swift
git commit -m "feat: PATH インストール用シムスクリプト生成ロジック CLIInstaller を追加する"
```

---

### Task 4: Menu item + `AppDelegate.installCLI(_:)` + result alert

**Files:**
- Create: `BefoldApp/befold/App/CLIInstallUI.swift`
- Modify: `BefoldApp/befold/App/MainMenuBuilder.swift:29-33` (insert after `checkForUpdates`)
- Modify: `BefoldApp/befold/App/AppDelegate.swift` (add `installCLI(_:)` action)
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`
- Test: `BefoldApp/befoldTests/MainMenuBuilderTests.swift`

**Interfaces:**
- Consumes: `CLIInstaller.install(bundlePath:installPath:) -> Result<Void, CLIInstallError>` (Task 3).
- Produces: `AppDelegate.installCLI(_ sender: Any?)` (`@objc`, wired as the menu item's action), `CLIInstallUI.presentInstallSucceeded()`, `CLIInstallUI.presentInstallFailed()`.

- [ ] **Step 1: Add localization keys**

In `BefoldApp/befold/Resources/Localizable.xcstrings`, insert a new `menu.app.installCLI` entry right after `"menu.app.checkForUpdates"` (before `"menu.app.services"`, currently at line 18). Replace:

```
    "menu.app.checkForUpdates" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Check for Updates…" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "アップデートを確認…" } }
      }
    },
    "menu.app.services" : {
```

with:

```
    "menu.app.checkForUpdates" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Check for Updates…" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "アップデートを確認…" } }
      }
    },
    "menu.app.installCLI" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Install 'befold' command in PATH" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "PATH に 'befold' コマンドをインストール" } }
      }
    },
    "menu.app.services" : {
```

Also append two more keys after `"cli.folder.noSupportedFile"` (added in Task 2, now the last entry before the closing `},`). Replace:

```
    "cli.folder.noSupportedFile" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "No supported file found in this folder." } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "このフォルダーに対応ファイルが見つかりません。" } }
      }
    }
  },
```

with:

```
    "cli.folder.noSupportedFile" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "No supported file found in this folder." } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "このフォルダーに対応ファイルが見つかりません。" } }
      }
    },
    "cli.install.success" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Installed the 'befold' command to /usr/local/bin." } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "/usr/local/bin に 'befold' コマンドをインストールしました。" } }
      }
    },
    "cli.install.failed" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Failed to install the 'befold' command." } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "'befold' コマンドのインストールに失敗しました。" } }
      }
    }
  },
```

- [ ] **Step 2: Write the failing menu test**

Append to `BefoldApp/befoldTests/MainMenuBuilderTests.swift` (inside `MainMenuBuilderTests`, after `helpMenuIsRegistered`):

```swift
    @Test("App メニューに Install CLI 項目がある")
    func appMenuHasInstallCLIItem() throws {
        let mainMenu = buildMenu()
        let appMenu = try #require(mainMenu.items.first?.submenu)

        let installItem = try #require(
            appMenu.items.first { $0.action == #selector(AppDelegate.installCLI(_:)) }
        )
        #expect(installItem.title == localizedTitle("menu.app.installCLI"))
    }
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderTests`
Expected: FAIL with "type 'AppDelegate' has no member 'installCLI'"

- [ ] **Step 4: Create `CLIInstallUI`**

Create `BefoldApp/befold/App/CLIInstallUI.swift`:

```swift
import AppKit

/// CLI インストール結果の NSAlert 表示(GUI 層・自動テスト対象外)。
@MainActor
enum CLIInstallUI {
    static func presentInstallSucceeded() {
        presentInfo(message: String(localized: "cli.install.success", bundle: .l10n))
    }

    static func presentInstallFailed() {
        presentInfo(message: String(localized: "cli.install.failed", bundle: .l10n))
    }

    private static func presentInfo(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
```

- [ ] **Step 5: Add the menu item**

In `BefoldApp/befold/App/MainMenuBuilder.swift`, replace (lines 29-34):

```swift
        menu.addItem(
            withTitle: String(localized: "menu.app.checkForUpdates", bundle: .l10n),
            action: #selector(AppDelegate.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
```

with:

```swift
        menu.addItem(
            withTitle: String(localized: "menu.app.checkForUpdates", bundle: .l10n),
            action: #selector(AppDelegate.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "menu.app.installCLI", bundle: .l10n),
            action: #selector(AppDelegate.installCLI(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
```

- [ ] **Step 6: Add `AppDelegate.installCLI(_:)`**

In `BefoldApp/befold/App/AppDelegate.swift`, add after `checkForUpdates(_:)` (the last method in the class):

```swift
    /// メニューの「Install 'befold' command in PATH」。/usr/local/bin にシムスクリプトを設置する。
    @objc func installCLI(_ sender: Any?) {
        let installPath = URL(fileURLWithPath: "/usr/local/bin/befold")
        let result = CLIInstaller.install(bundlePath: Bundle.main.bundlePath, installPath: installPath)
        switch result {
        case .success:
            CLIInstallUI.presentInstallSucceeded()
        case .failure:
            CLIInstallUI.presentInstallFailed()
        }
    }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd BefoldApp && swift test --filter MainMenuBuilderTests`
Expected: PASS (all `MainMenuBuilderTests`, including the new one)

Run the full suite to confirm no regressions: `cd BefoldApp && swift test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
cd BefoldApp
git add befold/App/CLIInstallUI.swift befold/App/MainMenuBuilder.swift befold/App/AppDelegate.swift \
        befold/Resources/Localizable.xcstrings befoldTests/MainMenuBuilderTests.swift
git commit -m "feat: App メニューに PATH への befold コマンドインストール項目を追加する"
```

---

### Task 5: Manual verification

No automated test covers the OS-level install (writing to the real `/usr/local/bin`, the administrator-privileges prompt, or an actual `open -a` invocation from a terminal shell) or the WebView/GUI alert rendering — consistent with this project's convention that WebView/GUI layers are checked manually before release.

**Files:** none (verification only).

- [ ] **Step 1: Build and run the app**

Run: `cd BefoldApp && xcodegen generate && xcodebuild build -scheme befold`
Then launch the built app (or `swift run` if easier for local testing).

- [ ] **Step 2: Verify menu placement**

Open the App menu and confirm "Install 'befold' command in PATH" appears directly below "Check for Updates…".

- [ ] **Step 3: Verify install (writable case)**

If `/usr/local/bin` is already writable (e.g. Homebrew-owned on this Mac), click the menu item and confirm:
- The success alert appears.
- `cat /usr/local/bin/befold` shows a shell script containing the running app's bundle path.
- `ls -l /usr/local/bin/befold` shows executable permissions (`-rwxr-xr-x`).

- [ ] **Step 4: Verify install (elevation case)**

If not writable, temporarily `sudo chmod 000 /usr/local/bin` (or test on a clean install) to confirm the administrator-privileges prompt appears and, after entering the password, the script is written successfully. Restore permissions afterward.

- [ ] **Step 5: Verify `befold <file>`**

In a terminal: `befold /path/to/some/file.mmd` — confirm befold opens and displays that file.

- [ ] **Step 6: Verify `befold <directory>` with supported files**

`befold ~/some-folder-with-mmd-files` — confirm befold opens showing the alphabetically-first supported file, with the sidebar rooted at that folder.

- [ ] **Step 7: Verify `befold <directory>` with no supported files**

`befold ~/some-empty-or-unsupported-folder` — confirm the "No supported file found in this folder." alert appears and no viewer window opens.

- [ ] **Step 8: Regression check on existing file-open paths**

Confirm Finder double-click, drag-and-drop, File > Open, and Recent Documents still open files normally (Task 2's change must not affect these).
