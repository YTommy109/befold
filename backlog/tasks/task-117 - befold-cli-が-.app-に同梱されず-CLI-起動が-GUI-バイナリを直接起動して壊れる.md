---
id: TASK-117
title: befold-cli が .app に同梱されず CLI 起動が GUI バイナリを直接起動して壊れる
status: In Progress
assignee:
  - '@claude'
created_date: '2026-07-24 02:50'
updated_date: '2026-07-24 03:51'
labels: []
dependencies: []
priority: high
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-108 の CLI バイナリ分離で `CLIInstaller.targetExecutablePath` は `befold.app/Contents/MacOS/befold-cli` を指すようになったが、`befold-cli` ターゲットをアプリバンドルへ同梱するビルド設定が入っていない。

## 現象（ユーザー報告）
`befold README.md` をコマンドラインから実行すると:
1. Dock に別の befold アイコン（汎用アイコン）が表示され、別バイナリが起動しているように見える
2. メニューバーが崩れ、`menu.file.title` / `menu.edit.title` / `menu.view.title` などのローカライズキーがそのまま表示される
3. `Sparkle updater failed to start: Sparkle cannot target a bundle that does not have a valid bundle identifier for bin` が出力され、プロセスが終了せず起動したままになる

## 原因
`/usr/local/bin/befold` の symlink 先が GUI 本体 `befold.app/Contents/MacOS/befold` になっており、GUI バイナリが .app の外のパス経由で直接起動される。この場合 `Bundle.main` が `/usr/local/bin` に解決されるため、

- Info.plist が無く bundle identifier を取得できない → Sparkle が起動失敗（エラー文言の末尾 `for bin` は `/usr/local/bin` を指す）
- `Bundle.l10n`（= `Bundle.main`、BefoldApp/befold/App/LocalizedBundle.swift:11）が Localizable.xcstrings を解決できない → メニュー項目がローカライズキーのまま表示される
- LaunchServices を経由しないため Dock に汎用アイコンの別インスタンスとして出る

という 3 症状すべてが同一原因から発生する。

## 未実装箇所
- BefoldApp/project.yml:99-105 — `befold` アプリターゲットの `dependencies` に `befold-cli` ターゲットが無く、`Contents/MacOS/` へのコピーフェーズも無い。実際 `/Applications/befold.app/Contents/MacOS/` には `befold` しか存在しない
- scripts/create-dmg.sh・.github/workflows/release.yml にも `befold-cli` への言及が無く、リリース成果物にも同梱されない
- 設計書 docs/superpowers/specs/2026-07-23-cli-binary-separation-design.md:5 は「CLI は `befold.app/Contents/MacOS/befold-cli` に同梱」と記載しており、同梱ステップだけが TASK-108 のサブタスクから漏れていた

なお `CLIShimInspector` は旧 shim を `staleSymlink` と判定する実装が既にあるため（BefoldApp/befold/App/CLIShimInspector.swift:19-29）、同梱さえ実現すれば再インストール導線は機能する見込み。ただし同梱前は再インストールしてもダングリング symlink になる点に注意。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ビルドした befold.app の Contents/MacOS/befold-cli が実行ファイルとして存在する
- [x] #2 /usr/local/bin/befold から CLI をインストールし直すと symlink 先が Contents/MacOS/befold-cli になり、`befold <path>` がファイルを開いた後に CLI プロセスが正常終了する
- [x] #3 CLI 起動時にメニューバーがローカライズされた文言で表示され、ローカライズキーがそのまま出ない
- [x] #4 CLI 起動時に Sparkle の bundle identifier エラーが出力されない
- [ ] #5 CLI 起動したウィンドウが Dock 上で既存の befold.app と同一アプリとして扱われ、別アイコンが増えない
- [ ] #6 DMG / リリース成果物に befold-cli が含まれ、コード署名・公証が通る
- [x] #7 CLI から既に起動中の befold インスタンスへファイルを転送でき、二重起動しない（CLIInstanceRouter が befold-cli 上で機能する）
- [x] #8 DMG 検証ジョブが befold.app/Contents/MacOS/befold-cli の存在を検証する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 調査結果の確定: Bundle.main が symlink 経由起動でどこに解決されるかを実測し、CLIInstanceRouter への影響を確認する
2. project.yml: befold アプリターゲットの dependencies に befold-cli を追加し、embed: true / link: false / codeSign: true / copy: {destination: executables} で Contents/MacOS へ同梱する。befold-cli ターゲットにも ENABLE_HARDENED_RUNTIME を付与する
3. CLIInstanceRouter.runningInstance() の Bundle.main.bundleIdentifier 依存を GUI アプリのバンドル ID 定数へ置き換え、BefoldCLICommand の "com.degino.befold" リテラルと共通化する（同じ値の三重管理を避ける）
4. テスト: (a) バンドル ID 定数の共通化を検証するユニットテスト、(b) project.yml が befold-cli を app ターゲットへ同梱設定していることを検証するテスト（既存 projectYmlMarketingVersionMatchesAppVersionConstant と同型）
5. release.yml の DMG 内容検証に Contents/MacOS/befold-cli の存在チェックを追加する
6. xcodegen generate → xcodebuild build → Contents/MacOS/befold-cli の存在確認、および symlink 再インストール後の手動動作確認（メニュー・Sparkle・Dock・プロセス終了・既存インスタンスへの転送）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 追加調査メモ（起票時）

### 同梱後に併せて確認すべき箇所
- `.github/workflows/release.yml` は `-scheme befold` のみビルドし、L179 の DMG 検証も `test -x .../Contents/MacOS/befold` しか見ていない。befold-cli の存在検証も追加する
- `BefoldApp/befoldCLITests/BefoldCLIIntegrationTests.swift:106-114` は xcodebuild レイアウトで `befold.app/Contents/MacOS/befold-cli` を `#require` している。SPM レイアウト（L99-105）にフォールバックするため `swift test` では同梱漏れが露見しない

### 関連する潜在バグ（同梱だけでは解決しない可能性）
`BefoldApp/BefoldCLI/CLIInstanceRouter.swift:24` の `guard let bundleID = Bundle.main.bundleIdentifier else { return nil }` は、バンドルを持たない tool である befold-cli では nil になり `runningInstance()` が常に nil を返す恐れがある。同種の問題は `befold-cli/BefoldCLICommand.swift:86-91` で UserDefaults の `suiteName: "com.degino.befold"` 明示により回避済み。同梱後の動作確認時に、起動中インスタンスへの転送が実際に機能するかを確認すること。

### 参考
- 設計書: docs/superpowers/specs/2026-07-23-cli-binary-separation-design.md:5, :178-180
- 旧 shim 判定: BefoldApp/befold/App/CLIShimInspector.swift:19-29
- 再インストール導線: MainMenuBuilder.swift:40-41 → AppDelegate.swift:257-267 / CLIInstallUI.swift

## 実装 (2026-07-24)

### 根本原因の実測確認
最小の再現バイナリ(Info.plist を持つ fake.app + symlink)で `Bundle.main` の解決先を実測した:
- 直接実行 → `bundlePath=<...>/fake.app` / `bundleID=com.example.fake`
- symlink 経由 → `bundlePath=<symlink の置き場所>` / `bundleID=<nil>`

symlink は解決されない。これにより「メニューのローカライズキー露出」「Sparkle の bundle identifier エラー」「Dock の別アイコン」がすべて説明できる。

### 単純化の検討
「壊れた shim を検知して自動修復する」経路の新設は不要と判断した。`CLIShimInspector` が旧 shim を `staleSymlink` と判定して再インストールを案内する導線が既にあるため、`befold-cli` を同梱するだけで既存経路がそのまま機能する。新しい状態も分岐も増やしていない。

### 変更内容
1. `BefoldApp/project.yml` — befold アプリターゲットに `- target: befold-cli` を追加(`embed: true` / `link: false` / `codeSign: true` / `copy: {destination: executables}`)。befold-cli ターゲットに `ENABLE_HARDENED_RUNTIME: true` を追加(公証対策)
2. `BefoldApp/BefoldCLI/AppBundle.swift`(新規) — GUI アプリのバンドル ID 定数 `AppBundle.identifier`
3. `BefoldApp/BefoldCLI/CLIInstanceRouter.swift` — `runningInstance()` の `Bundle.main.bundleIdentifier` 依存を `AppBundle.identifier` に置換。symlink 経由起動では nil になり、起動中インスタンスへの転送が常に失敗して 10 秒後に "Timed out waiting for app to launch." で終了していた。テスト用に `runningApplications` クロージャの DI を追加
4. `BefoldApp/befold-cli/BefoldCLICommand.swift` — bookmarkStore の suiteName リテラルを `AppBundle.identifier` に統一(同一値の三重管理を解消)
5. `BefoldApp/befold-cli/CLIAppLauncher.swift` — `findRunningInstance` 既定値を関数参照からクロージャへ(3 のシグネチャ変更に追随)
6. `.github/workflows/release.yml` — DMG 内容検証に `Contents/MacOS/befold-cli` の実行可能チェックを追加

### テスト (TDD)
- `befoldTests/CLIInstanceRouterTests.swift` — 「runningInstance は Bundle.main ではなく befold.app のバンドル ID で探索する」。RED は `queried == []`(Bundle.main.bundleIdentifier が nil で探索自体が走らない)を実際に観測してから修正
- `befoldCLITests/ProjectYmlPackagingTests.swift`(新規) — project.yml のアプリターゲットブロックを切り出し、befold-cli 同梱設定と PRODUCT_BUNDLE_IDENTIFIER の一致を検証。RED は同梱設定追加前に観測

### 検証結果
- `xcodegen generate` + `xcodebuild build -scheme befold` → `befold.app/Contents/MacOS/befold-cli` が生成される(214KB, 実行可能)
- `codesign --verify --deep --strict` → `valid on disk` / `satisfies its Designated Requirement`
- symlink 経由 `befold --version` → `1.7.2`(Info.plist を .app 側から解決できている)
- symlink 経由 `befold --check <path>` → `Can open: ...` / exit 0
- symlink 経由 `befold <file>` → 起動中インスタンスへ 0.04 秒で転送、exit 0、新規プロセスなし
- `swift build` / `swift test`(600 tests) / `npx jest`(203) すべて green

### 残: 手動確認が必要な項目
AC #3(メニューのローカライズ) / #4(Sparkle エラー) / #5(Dock アイコン)は、befold が起動していない状態からの CLI コールドスタートでの確認が必要。

## コールドスタート手動検証 (2026-07-24, ユーザー承認のうえ実施)

起動中の befold を終了し、Debug ビルドの `befold.app/Contents/MacOS/befold-cli` への symlink 経由で `befold README.md` を実行して確認した。

- 新規プロセスが `.../Debug/befold.app/Contents/MacOS/befold` として起動(`.app` バンドル経由)、exit 0
- メニューバー: `Apple, befold, ファイル, 編集, 表示, ウインドウ, ヘルプ` — ローカライズキーの露出なし (AC #3)
- `log show --predicate 'process == "befold"'` に Sparkle / bundle identifier 関連のエラー出力なし (AC #4)
- ウィンドウタイトル `README.md` — 指定ファイルが実際に開いた
- System Events のアプリ一覧に通常の GUI アプリ `befold` として 1 つだけ出現。CLIShimInspector の「コマンドラインツールを再インストール」バナーも期待どおり表示された

Dock について: 検証中は Dock に befold のタイルが 2 つ見えたが、これは /Applications/befold.app の常駐タイルとは別パス(ビルドディレクトリ)の Debug コピーを起動したため。リリースビルドを /Applications に配置すれば同一パスとなり 1 つに収束する。ユーザー報告の「汎用アイコンの別バイナリ」現象(バンドル外プロセス)は解消している。

検証後、Debug アプリを終了し /Applications/befold.app を再起動して環境を復旧済み。

## 残 AC (#5 / #6) について

いずれもローカルの Debug ビルドでは原理的に確定できないため未チェックのまま残す。

- **#5 (Dock)**: /Applications に配置したリリースビルドで確認する必要がある。ビルドディレクトリの別コピーを起動する検証では、常駐タイルと別パスになるため必ずタイルが 2 つになる
- **#6 (署名・公証)**: Developer ID 署名と公証はタグ push 時の release.yml でのみ実行される。ローカルでは adhoc 署名で `codesign --verify --deep --strict` が通ることまで確認済み

いずれも次回リリース時に release.yml の DMG 検証ステップ (#8 で追加) と併せて確定する。

## ユーザー向けの注意
既存の `/usr/local/bin/befold` は旧形式(GUI 本体を指す symlink)のままなので、befold-cli を含むビルドをインストールしたあとにメニューの「コマンドラインツールをインストール」を実行し直す必要がある。起動時に CLIShimInspector が staleSymlink を検知してバナーで案内する(検証中に表示を確認済み)。
<!-- SECTION:NOTES:END -->
