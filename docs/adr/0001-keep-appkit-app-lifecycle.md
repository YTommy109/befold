# ADR 0001: AppKit アプリライフサイクルを継続し SwiftUI App ライフサイクルへ移行しない

- ステータス: Accepted
- 日付: 2026-07-28
- backlog decision: decision-1

## Context

befold は現在 AppKit アプリライフサイクルで動作する。`AppDelegate` は `@main` 付きで、`NSApplication.run()` を
手動起動する。メニューは `MainMenuBuilder` が手組みする。全ビューは SwiftUI で書き、`NSHostingController` に
ホストしている。フォント設定ウィンドウの追加検討を機に、macOS 標準（SwiftUI `App`/`Scene`）へ移行するか検討した。
将来の OS 仕様変更に追随しやすくなるという観点で、その是非を評価した。

論点の正体は「AppKit／SwiftUI」の二択ではない。実際は
**「`@main`／シーン／ウィンドウのライフサイクルを誰が所有するか」** である。選択肢は次の3つ:

- **(A) 現状維持** — AppKit ライフサイクル（`AppDelegate` 所有）＋ SwiftUI ビュー
- **(B) ハイブリッド** — `NSApplicationDelegateAdaptor` で SwiftUI `App` に移行しつつ `AppDelegate` は残す
- **(C) フル移行** — SwiftUI `App`/`Scene`（`WindowGroup` か `DocumentGroup`）＋ `Settings`/`MenuBarExtra` 等

結合点調査では、プロダクトコード約13ファイルが AppKit ライフサイクル API を参照していた。
そこで判明した befold の作り込みは、SwiftUI ウィンドウモデルが歴史的に最も弱い領域と重なる:

| befold の作り込み | 実装 | 補足 |
| --- | --- | --- |
| ネイティブ NSWindow タブの明示制御 | `ViewerWindowController` / `SessionRestorer` | `tabGroup` / `addTabbedWindow` / `selectedWindow` |
| セッション復元（タブ構成・順序・選択・アクティブ） | `SessionStore` / `SessionRestorer` | 完全自前実装。`NSWindowRestoration` は使わない |
| ウィンドウ寸法の永続化 | `WindowFrameStore` | 新規ウィンドウの出発点をアプリ全体で 1 個持つ |
| ウィンドウ寸法の永続化 | `SessionLayout.TabGroup.frame` | 再起動時に窓ごとの寸法へ戻す |
| CLI から特定ウィンドウを開く/前面化 | `AppDelegate` / CLI 転送 | Distributed Notification → `openPaths` + `NSApp.activate` |
| 同一ファイルを複数ウィンドウで開く | `ViewerWindowManager` | 辞書で管理 |
| Sparkle 自動更新 | `AppDelegate` | `SPUStandardUpdaterController` / `SPUUpdaterDelegate` に結合 |

ウィンドウ寸法の URL 単位の記憶は ADR 0010 で廃止した。

これらはテスト網が薄く、挙動も微妙な部分である。フル移行(C)は最リスク領域の全面書き換えになる。

## Decision

**(A) AppKit アプリライフサイクルを継続する。** SwiftUI はビュー層で今後も積極的に採用する。
`@main`・シーン・ウィンドウ所有は AppKit（`AppDelegate` / `NSWindowController` / `ViewerWindowManager`）に置く。

根拠:

- SwiftUI ライフサイクルにしか自動で付かないのは、`Settings`/`DocumentGroup`/`MenuBarExtra` 等の**自動配線**だけである。
  その**挙動自体は AppKit でも再現できる**。befold は既にネイティブタブ・Recents・Services メニュー等の
  標準挙動を採り入れており、「標準に乗る」目的の大半は達成済み。
- 見た目・素材・コントロール・アクセシビリティ・外観追従といった macOS アップデートの大半は AppKit にも流れる。
  SwiftUI は macOS では AppKit の上の層であり、AppKit は非推奨ではない。SwiftUI 専用の新機能が要る場合も
  `NSHostingController` で AppKit アプリに差し込める（既存の方法）。
- `DocumentGroup` が無償提供する Recents/タブ/復元は befold が既に手で作り込み、より細かく制御している。
  移行はその制御を手放してフレームワークの流儀に合わせ直す作業で、得より損が勝つ。
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
- 実現可能性の確認が必要になった場合は、タイムボックス付き spike を別途起票する。spike は、現行 macOS で
  `WindowGroup`＋タブ＋per-window 復元＋外部起動がどこまで再現できるかを検証するプロトタイプである。
