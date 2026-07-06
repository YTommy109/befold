# mmdview → befold リネーム 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** アプリ・リポジトリ・モジュール・bundle identifier のすべてを `mmdview` から `befold` にリネームし、ビルド・テスト・CI・自動アップデートが一貫して動作する状態にする。

**Architecture:** `project.yml`（XcodeGen）を真実の源とし、そこと `Package.swift` を直したうえでディレクトリを `git mv`、ソース内の文字列・識別子・URL を更新、テストの `@testable import` と CI/スクリプト/現行ドキュメントを追随させ、最後に `xcodegen generate` → ビルド/テストで検証し、GitHub リポジトリを改名する。生成物（`*.xcodeproj`）は手修正せず再生成する。

**Tech Stack:** Swift 6 / AppKit + SwiftUI, XcodeGen, Swift Package Manager, GitHub Actions, `gh` CLI, macOS 14+。

## Global Constraints

- 新名称は小文字 `befold`（モジュール名・`PRODUCT_NAME`・表示名すべて）。トップディレクトリのみ CamelCase `BefoldApp`。
- `bundleIdPrefix` は `com.degino` を維持。bundle identifier は `com.degino.befold`、テストは `com.degino.befoldTests`、UTI は `com.degino.befold.mermaid-diagram` / `com.degino.befold.source-code`。
- GitHub owner は `YTommy109` を維持。リポジトリ名のみ `mmdview` → `befold`。コード内 URL は `github.com/YTommy109/befold`・`api.github.com/repos/YTommy109/befold`。
- `docs/superpowers/plans/` と `docs/superpowers/specs/` の過去履歴は **置換しない**（本計画ファイル自身を除く）。現行ドキュメント（README・`.claude/`・`docs/coding_rule.md`・`docs/native-app-design.md`）のみ befold 化。
- 自動アップデートの DMG/`.app` 判定は拡張子ベースなので DMG 名変更は機能に影響しない。
- 作業ブランチは `feat/rename`。各タスク末尾でコミット。関連する変更は前コミットへ `--amend` せず、フェーズ単位の独立コミットにする（レビュー可能性優先）。

---

### Task 0: ベースライン確認

**Files:** なし（読み取りのみ）

- [ ] **Step 1: 現行のビルド/テストがグリーンなことを確認**

Run:
```bash
cd /Users/tokutomi/.superset/worktrees/mmdview/feat/rename/MmdviewApp
swift build
swift test
```
Expected: 両方成功。失敗する場合はリネーム前に原因を切り分ける（リネーム起因の失敗と区別するための基準線）。

- [ ] **Step 2: mmdview 全出現の件数を記録（後段の取りこぼし検出用）**

Run:
```bash
cd /Users/tokutomi/.superset/worktrees/mmdview/feat/rename
grep -rniI mmdview --exclude-dir=.git --exclude-dir=docs/superpowers . | wc -l
```
Expected: 数値が出る（履歴 docs を除いた現行の総出現数）。この数を控えておき、Task 9 で 0 に近づくことを確認する。

---

### Task 1: ビルド構成の中核（project.yml / Package.swift）

**Files:**
- Modify: `MmdviewApp/project.yml`
- Modify: `MmdviewApp/Package.swift`

**Interfaces:**
- Produces: モジュール名 `befold`、テストモジュール `befoldTests`、`PRODUCT_NAME=befold`、`PRODUCT_BUNDLE_IDENTIFIER=com.degino.befold`。以降のタスクの import 文・パス参照はこの名前に依存する。

> このタスクでは `project.yml` / `Package.swift` 内の**パス参照はまだ `mmdview/` のまま**にしておき、Task 2 のディレクトリ mv と同時に整合させる。ここで変えるのは名称系（`name` / `PRODUCT_NAME` / bundle id / target 名 / TEST_HOST の app・実行ファイル名）に留める。

- [ ] **Step 1: project.yml の名称を更新**

`MmdviewApp/project.yml` を次のように変更（`bundleIdPrefix: com.degino` は据え置き）:
- `name: mmdview` → `name: befold`
- app ターゲットキー `mmdview:` → `befold:`
- `PRODUCT_BUNDLE_IDENTIFIER: com.degino.mmdview` → `com.degino.befold`
- `PRODUCT_NAME: mmdview` → `PRODUCT_NAME: befold`
- テストターゲットキー `mmdviewTests:` → `befoldTests:`
- 依存 `- target: mmdview` → `- target: befold`
- `TEST_HOST: "$(BUILT_PRODUCTS_DIR)/mmdview.app/Contents/MacOS/mmdview"` → `.../befold.app/Contents/MacOS/befold`

（`path:` / `sources:` / `INFOPLIST_FILE:` / `CODE_SIGN_ENTITLEMENTS:` の `mmdview/...` パスは Task 2 で更新する）

- [ ] **Step 2: Package.swift の名称を更新**

`MmdviewApp/Package.swift`:
- `name: "mmdview"`（package）→ `"befold"`
- executableTarget `name: "mmdview"` → `"befold"`
- testTarget `name: "mmdviewTests"` → `"befoldTests"`
- testTarget `dependencies: ["mmdview"]` → `["befold"]`

（`path:` / `exclude:` のパスは Task 2 で更新）

- [ ] **Step 3: コミット**

```bash
cd /Users/tokutomi/.superset/worktrees/mmdview/feat/rename
git add MmdviewApp/project.yml MmdviewApp/Package.swift
git commit -m "chore: ビルド構成の名称を mmdview から befold に変更する"
```

---

### Task 2: ディレクトリ/ファイルの git mv とパス整合

**Files:**
- Rename: `MmdviewApp/` → `BefoldApp/`
- Rename: `BefoldApp/mmdview/` → `BefoldApp/befold/`
- Rename: `BefoldApp/mmdviewTests/` → `BefoldApp/befoldTests/`
- Rename: `BefoldApp/befold/mmdview.entitlements` → `BefoldApp/befold/befold.entitlements`
- Delete: `BefoldApp/mmdview.xcodeproj/`（Task 8 で再生成）
- Modify: `BefoldApp/project.yml`, `BefoldApp/Package.swift`（パス参照）

- [ ] **Step 1: ディレクトリ/ファイルを git mv**

```bash
cd /Users/tokutomi/.superset/worktrees/mmdview/feat/rename
git mv MmdviewApp/mmdview/mmdview.entitlements MmdviewApp/mmdview/befold.entitlements
git mv MmdviewApp/mmdview MmdviewApp/befold
git mv MmdviewApp/mmdviewTests MmdviewApp/befoldTests
git rm -r MmdviewApp/mmdview.xcodeproj
git mv MmdviewApp MmdviewApp.tmp && git mv MmdviewApp.tmp BefoldApp
```
（大文字小文字のみの差異を case-insensitive FS でも確実に反映するため二段階 mv）

- [ ] **Step 2: project.yml / Package.swift のパス参照を更新**

`BefoldApp/project.yml`:
- `path: mmdview` → `path: befold`
- `sources` 等 `mmdview/Resources`, `mmdviewTests`, `mmdview/Info.plist` → `befold/...`, `befoldTests`
- excludes `mmdview.entitlements` → `befold.entitlements`
- `INFOPLIST_FILE: mmdview/Info.plist` → `befold/Info.plist`
- `CODE_SIGN_ENTITLEMENTS: mmdview/mmdview.entitlements` → `befold/befold.entitlements`

`BefoldApp/Package.swift`:
- executableTarget `path: "mmdview"` → `"befold"`
- `exclude: ["Info.plist", "mmdview.entitlements", ...]` → `"befold.entitlements"`
- testTarget `path: "mmdviewTests"` → `"befoldTests"`

- [ ] **Step 3: コミット**

```bash
git add -A
git commit -m "chore: ソース/テストディレクトリを befold にリネームする"
```

---

### Task 3: ソースコード内の識別子・URL・文字列

**Files:**
- Modify: `BefoldApp/befold/Info.plist`（`:8` CFBundleDisplayName, `:33/76/152/189` UTI）
- Modify: `BefoldApp/befold/FileWatching/FileWatcher.swift:35`
- Modify: `BefoldApp/befold/Updates/ReleaseFetcher.swift:6`
- Modify: `BefoldApp/befold/App/AppDelegate.swift:126,128`
- Modify: `BefoldApp/befold/Updates/UpdateFlowController.swift:37,66,76`
- Modify: `BefoldApp/befold/Resources/viewer.html:15`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`（5 キー）

- [ ] **Step 1: Info.plist の表示名と UTI**

- `CFBundleDisplayName` の値 `mmdview` → `befold`
- UTI `com.degino.mmdview.mermaid-diagram` → `com.degino.befold.mermaid-diagram`（`:33`, `:152`）
- UTI `com.degino.mmdview.source-code` → `com.degino.befold.source-code`（`:76`, `:189`）

- [ ] **Step 2: GCD ラベル・URL・一時ファイル名**

- `FileWatcher.swift:35`: `com.degino.mmdview.filewatcher` → `com.degino.befold.filewatcher`
- `ReleaseFetcher.swift:6`: `https://api.github.com/repos/YTommy109/mmdview/releases/latest` → `.../YTommy109/befold/releases/latest`
- `AppDelegate.swift:128`: `https://github.com/YTommy109/mmdview#readme` → `.../YTommy109/befold#readme`、`:126` のコメント `mmdview Help` → `befold Help`
- `UpdateFlowController.swift`: `mmdview-update.dmg`（`:37`）, `Logs/mmdview-updater.log`（`:66`）, `mmdview-updater.sh`（`:76`）をそれぞれ `befold-*` に

- [ ] **Step 3: viewer.html と Localizable.xcstrings**

- `viewer.html:15`: `<title>mmdview</title>` → `<title>befold</title>`
- `Localizable.xcstrings` の以下キーの en/ja 値内の `mmdview` を `befold` に置換:
  - `menu.app.about`（"About mmdview" / "mmdview について"）
  - `menu.app.hide`（"Hide mmdview" / "mmdview を隠す"）
  - `menu.app.quit`（"Quit mmdview" / "mmdview を終了"）
  - `menu.help.appHelp`（"mmdview Help" / "mmdview ヘルプ"）
  - 更新通知キー（"mmdview %@ is available" / "mmdview %@ が利用可能です"）

- [ ] **Step 4: コミット**

```bash
git add BefoldApp/befold
git commit -m "feat: アプリ表示名・識別子・更新 URL を befold に変更する"
```

---

### Task 4: テストの追随

**Files:**
- Modify: `BefoldApp/befoldTests/*.swift`（全 import）
- Modify: `BefoldApp/befoldTests/InfoPlistTests.swift`（`:15` パス, `:65/77/93` UTI）
- Modify: `BefoldApp/befoldTests/LocalizationTests.swift:35,36`
- Modify: `BefoldApp/befoldTests/GitHubReleaseTests.swift`, `UpdateCheckerTests.swift`（URL・DMG 名）
- Modify: 一時ファイル/パスをハードコードするテスト（`TestSupport.swift`, `DMGMounterTests.swift`, `UpdateInstaller*Tests.swift`, `FileWatcherIntegrationTests.swift`, `ViewerBridgeTests.swift` ほか）

- [ ] **Step 1: import 文を一括置換**

```bash
cd /Users/tokutomi/.superset/worktrees/mmdview/feat/rename
grep -rl 'import mmdview' BefoldApp/befoldTests | xargs sed -i '' 's/import mmdview/import befold/g'
```
確認: `grep -rn 'import mmdview' BefoldApp/befoldTests` が 0 件。

- [ ] **Step 2: UTI・表示文字列・URL・DMG 名のハードコードを置換**

`BefoldApp/befoldTests` 配下で以下を befold に置換（機械置換 → 目視確認）:
- UTI `com.degino.mmdview.` → `com.degino.befold.`（`InfoPlistTests.swift`）
- 表示文字列 `mmdview を終了` / `Quit mmdview`（`LocalizationTests.swift`）
- URL `YTommy109/mmdview` → `YTommy109/befold`、DMG/ZIP アセット名 `mmdview-v1.2.0` → `befold-v1.2.0`（`GitHubReleaseTests.swift`, `UpdateCheckerTests.swift`）
- `.app` / パス `mmdview.app`, `mmdview/Info.plist`, `mmdview/Resources` → `befold.*`（`UpdateInstaller*Tests.swift`, `InfoPlistTests.swift`, `ViewerBridgeTests.swift`）
- 一時ファイル prefix `mmdview-test` / DMG ボリューム名 `mmdview v1.2.0` → `befold-*`（`TestSupport.swift`, `DMGMounterTests.swift`, `FileWatcherIntegrationTests.swift`, `UpdateFlowController` 由来のログ/スクリプト名を検証する箇所）

一括の下地（残りを目視で精査）:
```bash
grep -rl mmdview BefoldApp/befoldTests | xargs sed -i '' 's/mmdview/befold/g; s/Mmdview/Befold/g'
```
確認: `grep -rniI mmdview BefoldApp/befoldTests` が 0 件。

- [ ] **Step 3: コミット**

```bash
git add BefoldApp/befoldTests
git commit -m "test: テストの import と識別子・URL を befold に追随させる"
```

---

### Task 5: CI / パッケージング / スクリプト

**Files:**
- Modify: `.github/workflows/release.yml`, `verify-dmg.yml`, `ci.yml`
- Modify: `scripts/create-dmg.sh`, `scripts/bump.sh`, `scripts/webview-smoke.swift`
- Modify: `BefoldApp/scripts/build_icon.sh`

- [ ] **Step 1: GitHub Actions ワークフロー**

- `release.yml`: `DMG_NAME: mmdview-...dmg` → `befold-...dmg`、`-scheme mmdview` → `-scheme befold`、`Release/mmdview.app` → `Release/befold.app`、検証パス `mmdview.app/Contents/MacOS/mmdview` → `befold.*`、`working-directory: MmdviewApp` → `BefoldApp`
- `verify-dmg.yml`: ダミー `mmdview.app` 生成・`CFBundleName`/`CFBundleExecutable` の `mmdview`・create-dmg 引数・マウント検証パスを `befold` に
- `ci.yml`: paths フィルタ `MmdviewApp/**` → `BefoldApp/**`、working-directory・cache path・cache キーの `MmdviewApp` を `BefoldApp` に

- [ ] **Step 2: スクリプト**

- `scripts/create-dmg.sh`: `--volname "mmdview"` → `"befold"`、`--icon "mmdview.app"` → `"befold.app"`
- `scripts/bump.sh`: `PROJECT_YML="$ROOT/MmdviewApp/project.yml"` → `BefoldApp/project.yml`
- `scripts/webview-smoke.swift`: 既定パス `MmdviewApp/mmdview/Resources` → `BefoldApp/befold/Resources`
- `BefoldApp/scripts/build_icon.sh`: 出力パス `mmdview/Resources/AppIcon.icns` → `befold/Resources/AppIcon.icns`

- [ ] **Step 3: コミット**

```bash
git add .github scripts BefoldApp/scripts
git commit -m "ci: CI・パッケージングスクリプトを befold に更新する"
```

---

### Task 6: Claude / リポジトリ設定（フックパス）

**Files:**
- Modify: `.claude/settings.json`, `.claude/CLAUDE.md`, `.claude/agents/*.md`, `.claude/commands/*.md`, `.claude/skills/*.md`

> フック（`settings.json`）は `MmdviewApp/...` パスと `pkill -x mmdview` を参照するため、旧パスのままだと以降のビルド系フックが失敗する。Task 2 でディレクトリを mv した時点で壊れているので、ここで確実に直す。

- [ ] **Step 1: settings.json のフックを更新**

`.claude/settings.json` の `MmdviewApp/mmdview.xcodeproj` などのパスを `BefoldApp/...` に、`pkill -x mmdview` を `pkill -x befold` に更新（`:8,32,42,48,54,60`）。

- [ ] **Step 2: .claude ドキュメント一括置換**

```bash
cd /Users/tokutomi/.superset/worktrees/mmdview/feat/rename
grep -rl mmdview .claude | xargs sed -i '' 's/MmdviewApp/BefoldApp/g; s/mmdview/befold/g; s/Mmdview/Befold/g'
```
（`com.degino.befold.*`・`-scheme befold`・`pkill -x befold`・パスが正しく置換されたか目視確認）

- [ ] **Step 3: コミット**

```bash
git add .claude
git commit -m "chore: Claude 設定・フックパスを befold に更新する"
```

---

### Task 7: 現行ドキュメント

**Files:**
- Modify: `README.md`
- Modify: `docs/coding_rule.md`, `docs/native-app-design.md`
- 除外: `docs/superpowers/plans/`, `docs/superpowers/specs/`（本計画ファイルを除き据え置き）

- [ ] **Step 1: README と現行 docs を置換**

```bash
cd /Users/tokutomi/.superset/worktrees/mmdview/feat/rename
sed -i '' 's/MmdviewApp/BefoldApp/g; s/YTommy109\/mmdview/YTommy109\/befold/g; s/mmdview/befold/g; s/Mmdview/Befold/g' \
  README.md docs/coding_rule.md docs/native-app-design.md
```
確認: 見出し `# befold`、`-scheme befold`、`befold.app`、`befold-vX.Y.Z.dmg`、GCD ラベル `com.degino.befold.filewatcher`（coding_rule.md）、GitHub URL が `YTommy109/befold` になっていること。`docs/native-app-design.md` の appcast プレースホルダ URL は設計メモなので `befold` 化のみでよい。

- [ ] **Step 2: コミット**

```bash
git add README.md docs/coding_rule.md docs/native-app-design.md
git commit -m "docs: 現行ドキュメントを befold に更新する"
```

---

### Task 8: 再生成 & ローカル検証

**Files:**
- Generate: `BefoldApp/befold.xcodeproj`（`xcodegen generate` の生成物）

- [ ] **Step 1: Xcode プロジェクトを再生成**

```bash
cd /Users/tokutomi/.superset/worktrees/mmdview/feat/rename/BefoldApp
xcodegen generate
```
Expected: `befold.xcodeproj` が生成される（旧 `mmdview.xcodeproj` は Task 2 で削除済み）。

- [ ] **Step 2: SwiftPM ビルド/テスト**

```bash
swift build
swift test
```
Expected: 両方成功（Task 0 と同じテスト群がグリーン）。

- [ ] **Step 3: Xcode ビルド（xcstrings コンパイル経路の確認）**

```bash
xcodebuild build -scheme befold
```
Expected: 成功。`swift test` は xcstrings を生 JSON のまま扱うため、`.lproj` 化を伴う Xcode ビルドでも通ることを確認（メモ: swiftpm-xcstrings-not-compiled）。

- [ ] **Step 4: WebView スモーク & 生成物名の確認**

```bash
cd /Users/tokutomi/.superset/worktrees/mmdview/feat/rename
grep -rniI mmdview --exclude-dir=.git --exclude-dir=docs/superpowers .
```
Expected: 0 件（履歴 docs を除いた現行の残存がないこと）。残っていれば該当フェーズに戻して修正。加えて `/webview-smoke` でレンダリング疎通を確認。

- [ ] **Step 5: 生成物再生成分をコミット**

```bash
git add BefoldApp/befold.xcodeproj
git commit -m "chore: befold 名で Xcode プロジェクトを再生成する"
```

---

### Task 9: GitHub リポジトリ改名

**Files:** なし（リモート操作）

- [ ] **Step 1: リポジトリを改名**

```bash
cd /Users/tokutomi/.superset/worktrees/mmdview/feat/rename
gh repo rename befold --repo YTommy109/mmdview
```
Expected: `YTommy109/befold` に改名され、GitHub 側で旧名からのリダイレクトが有効になる。

- [ ] **Step 2: リモート URL を更新**

```bash
git remote set-url origin git@github.com:YTommy109/befold.git
git remote -v
```
Expected: origin が `YTommy109/befold` を指す。

- [ ] **Step 3: プッシュして PR を作成**

```bash
git push -u origin feat/rename
```
その後 PR を作成（`/pr`）。PR 本文に「Bundle ID 変更により既存インストールは別アプリ扱いになり Recent Documents 等がリセットされること」「旧バイナリの自動更新は GitHub リダイレクト頼みであること」を明記する。

- [ ] **Step 4: 追従が必要な外部設定の確認（手動）**

- ローカルワークツリー/親リポジトリのパス（`.superset/worktrees/mmdview/...`）はディレクトリ名なので任意。必要なら別途 worktree を切り直す。
- GitHub Pages / リリース設定など外部サービスに `mmdview` を参照する箇所がないか確認（本リポジトリ内には appcast 実装なし）。

---

## Self-Review

- **Spec coverage:** 4 つの確定方針（リポジトリ名 / bundle id・UTI / ディレクトリ・モジュール / 履歴 docs 据え置き）はそれぞれ Task 9 / Task 3・1 / Task 1・2・4 / Task 7 でカバー。3 調査エージェントが挙げた全ファイル分類（Swift・リソース・ビルド設定・CI・スクリプト・.claude・現行 docs・GitHub URL）に対応タスクあり。
- **残存検出:** Task 0 と Task 8-Step4 の `grep -rniI mmdview`（履歴 docs 除外）で取りこぼしを機械的に検出する。
- **Type consistency:** モジュール名 `befold` / テスト `befoldTests` / `PRODUCT_NAME=befold` / bundle id `com.degino.befold` を全タスクで統一。ディレクトリは `BefoldApp/befold/` と `BefoldApp/befoldTests/`。
- **既知の落とし穴:** フックパス（Task 6）は mv 直後に直さないと以降のビルド系フックが旧パスで失敗する。case-insensitive FS での `MmdviewApp→BefoldApp` は二段階 mv（Task 2-Step1）で対処。
