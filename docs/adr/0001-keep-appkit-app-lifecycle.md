# ADR 0001: AppKit アプリライフサイクルを継続し SwiftUI App ライフサイクルへ移行しない

- ステータス: Accepted
- 日付: 2026-07-28
- backlog decision: decision-1

## Context

befold は現在 AppKit アプリライフサイクル（`@main` 付き `AppDelegate` が `NSApplication.run()` を手動起動、
`MainMenuBuilder` がメニューを手組み）で動作し、全ビューは SwiftUI で書いて `NSHostingController` で
ホストしている。フォント設定ウィンドウの追加検討をきっかけに、macOS 標準（SwiftUI `App`/`Scene`）に
乗ることで将来の OS 仕様変更の恩恵を最大化できるのではないか、という観点で移行の是非を評価した。

論点の正体は「AppKit か SwiftUI か」ではなく **「`@main`／シーン／ウィンドウのライフサイクルを誰が所有するか」**。
選択肢は次の3つ:

- **(A) 現状維持** — AppKit ライフサイクル（`AppDelegate` 所有）＋ SwiftUI ビュー
- **(B) ハイブリッド** — `NSApplicationDelegateAdaptor` で SwiftUI `App` に移行しつつ `AppDelegate` は残す
- **(C) フル移行** — SwiftUI `App`/`Scene`（`WindowGroup` か `DocumentGroup`）＋ `Settings`/`MenuBarExtra` 等

結合点調査（プロダクトコード約13ファイルが AppKit ライフサイクル API を参照）で判明した befold の作り込みは、
そのまま SwiftUI ウィンドウモデルが歴史的に最も弱い領域と重なる:

| befold の作り込み | 実装 |
| --- | --- |
| ネイティブ NSWindow タブの明示制御 | `tabGroup`/`addTabbedWindow`/`selectedWindow`（`ViewerWindowController`/`SessionRestorer`） |
| セッション復元（タブ構成・順序・選択・アクティブ） | 完全自前実装、NSWindowRestoration 不使用（`SessionStore`/`SessionRestorer`） |
| ウィンドウ寸法の永続化 | `WindowFrameStore`（新規ウィンドウの出発点をアプリ全体で 1 個）と `SessionLayout.TabGroup.frame`（再起動時に窓ごとへ戻す）。URL 単位の記憶は ADR 0010 で廃止した |
| CLI から特定ウィンドウを開く/前面化 | Distributed Notification → `openPaths` + `NSApp.activate`（`AppDelegate`/CLI 転送） |
| 同一ファイルを複数ウィンドウで開く | `ViewerWindowManager` の辞書管理 |
| Sparkle 自動更新 | `AppDelegate` に結合（`SPUStandardUpdaterController`/`SPUUpdaterDelegate`） |

これらは最もテスト網が薄く挙動が微妙な部分であり、フル移行(C)は最リスク領域の全面書き換えになる。

## Decision

**(A) AppKit アプリライフサイクルを継続する。** SwiftUI はビュー層で今後も積極的に採用するが、
`@main`・シーン・ウィンドウ所有は AppKit（`AppDelegate` / `NSWindowController` / `ViewerWindowManager`）に置く。

根拠:

- 「macOS 標準に乗る」で SwiftUI ライフサイクルにしか自動で付かないのは `Settings`/`DocumentGroup`/`MenuBarExtra`
  等の**自動配線**に限られ、その**挙動自体は AppKit でも再現可能**。befold は既にネイティブタブ・Recents・
  Services メニュー等の標準挙動を採り入れており、「標準に乗る」目的の大半は達成済み。
- macOS の見た目・素材・コントロール・アクセシビリティ・外観追従といった OS アップデートの大半は AppKit にも流れる
  （SwiftUI は macOS では AppKit の上の層で、AppKit は非推奨ではない）。SwiftUI 専用の新機能が要る場合も
  `NSHostingController` で AppKit アプリに差し込める（既存の方法）。
- `DocumentGroup` が無償提供する Recents/タブ/復元は befold が既に手で作り込み、より細かく制御している。
  移行はその制御を手放してフレームワークの流儀に合わせ直す作業になり、得より損が勝つ。
- (B) ハイブリッドは「シーンにウィンドウ所有を委ねる」前提でなければ旨みが薄く、AppDelegate が全 NSWindow を
  手生成し続けるなら二重管理で混乱が増えるだけ。中途半端な採用は避ける。

## Consequences

- 設定ウィンドウ等は、既存の「`NSWindowController` が SwiftUI をホストする」パターンで自前配線する
  （`Settings` シーンの自動配線は使わない）。
- SwiftUI ビューの拡充は継続する。ライフサイクル移行はしないが、ビュー層のモダン化は妨げない。
- 将来この決定を再検討するトリップワイヤ（**すべて揃ったとき**に再評価する）:
  1. 最低 OS ターゲットが上がり、SwiftUI シーンがプログラム的な多ウィンドウ＋タブ＋per-window 復元を十分カバーする水準になる
  2. 具体的に欲しい機能が SwiftUI ライフサイクルでしか実現できず、`NSHostingController` でも橋渡しできない
  3. 手組みのウィンドウ／セッションコードの保守負担が、その価値に見合わないほど膨らむ
- 実現可能性を本気で確かめたくなった場合は、タイムボックス付き spike（現行 macOS で `WindowGroup`＋タブ＋
  per-window 復元＋外部起動がどこまで再現できるかの検証プロトタイプ）を別途起票する。
