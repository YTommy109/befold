---
id: TASK-388
title: 文書の状態を窓のライブ値優先にし、生きている間は保存値を読み直さない
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-09 10:12'
updated_date: '2026-08-09 11:28'
labels: []
dependencies:
  - TASK-382
priority: medium
type: bug
ordinal: 515000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0002「状態の所在」で決めた原則を実装へ反映する（TASK-382 で決定）。

## 原則

文書の状態（ズーム倍率・スクロール位置・表示モード）は、**窓が生きている間はその窓のライブ値が有効**。ファイル単位の保存値は「その文書を次に開くときの既定値」であって、開いている窓へ後から効くものではない。窓を閉じるとライブ値は消え、次に開いたときは保存値から始まる。

窓間の同期は行わない。同じファイルを 2 つの窓で開いて別々の倍率・位置・モードで読むのは、食い違いではなく正常な使い方である。

## 変更点

1. **保存値を読み直すのは「窓がその文書を提示し始めるとき」だけにする**（オープン・ファイル切替・リネーム）。生きている窓が再ロード等で読み直す経路を塞ぐ。現状 ViewerWindowController.swift:491 が再ロード時に applyStoredZoom() を呼ぶため、窓 B が他窓の書いた値を拾う（ズーム = 旧 TASK-388、スクロール位置 = 旧 TASK-390 の症状はどちらもこれ）。
2. **表示モードの窓間同期を撤去する**。ViewerWindowController.setDisplayMode 完了時のデリゲート通知 → ViewerWindowManager.mirrorDisplayMode（ViewerWindowManager.swift:183-189）→ ViewerWindowController.mirrorDisplayMode（:734-739）と、対応するテストを削除する。TASK-371 で入れた同期を、上記の原則に沿って巻き戻す変更である。
3. ADR 0002 の「表示モードの遷移仕様」から、同期を前提にした記述（遷移表の『他ウィンドウからの同期』行、cmd+U の戻り先を同期経路でも破棄する記述、複数ウィンドウの不変条件節）を実装に合わせて整合させる。ADR 側は TASK-382 で先に書き換えてあるので、実装がそこへ追いつく形になる。

## 決めたこと（再確認不要）

- **アプリ再起動時、同じファイルを開いていた 2 窓が同じ値で復元されるのは許容する。** 窓の識別子は導入しない（SessionLayout は groups: [TabGroup] でパスの並びしか持たない）。したがって新しい永続化は不要で、変更は上記 1・2 に収まる。
- 行番号表示は既にこの形（窓ごとのライブ値 + アプリ全体の既定値）なので対象外。

## 対象外

アプリの好みに属する状態（差分レイアウト・検索オプション・コードフォント・隠しファイル表示・変更ファイルのみ表示）は従来どおり 1 インスタンス共有で全窓へ即時反映する。この原則は文書の状態にのみ適用する。

着手前に /review-design を回すこと（既存の共通経路と不変条件を撤去する変更のため）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 同じファイルを 2 つのウィンドウで開き、片方でズーム・スクロール・表示モードを変えても、もう一方は変わらない。生きている窓は保存値を読み直さないため、再ロードや他窓の保存が後から効くことがない
- [x] #2 その窓自身が文書を提示し直す契機（オープン・ファイル切替・モード切替）では保存値を読む。この 3 契機以外に読み手が無い（起票時の AC#1 は『ファイル切替を挟んでも拾わない』と書いていたが、ADR 0002 の決定はファイル切替を提示開始として保存値を読む側なので、実装に合わせて条件を分割した）
- [x] #3 ウィンドウを閉じて同じファイルを開き直すと、最後に設定した値（保存値）から始まる
- [x] #4 表示モードの窓間同期の経路（mirrorDisplayMode とデリゲート通知）が撤去され、同期を前提にしたテストが削除または書き換えられている
- [x] #5 上記の振る舞いが破れたら落ちるテストがある（提示開始で読む処理を消す／窓間同期を戻す、のいずれでも落ちることを実測済み）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
/review-design 実施済み。指摘を反映した方針。

【原則】保存値（ZoomStore / ScrollPositionStore / DisplayModeStore）を読むのは窓が文書を提示し始めるときだけ。生きている間は窓のライブ値が有効。窓間の同期はしない。

1. ライブ値の置き場は新設せず ViewerStore（既存の窓ごと @Observable）に置く。ADR が手本とする showLineNumbers と同じ場所。新しい型・新しい注入経路を増やさない。
2. ViewerContentView から zoomStore / scrollPositionStore の引数自体を撤去する（渡らないから読めない構造にする＝項目 9 の担保）。ViewerWebView へは ViewerStore のライブ値を渡す。
3. WebViewCommandController.applyStoredZoom() を撤去し、経路を 1 本にする（保存値の読み手が 2 箇所あるのをやめる＝項目 3）。
4. 保存値を読む提示開始の契機は 3 つに限定する。
   - ViewerWindowController.init（オープン）: ライブ倍率・ライブスクロール復元位置を保存値から設定
   - performFileSwitch（ファイル切替）: 切替先 URL の保存値から設定（applyStoredZoom の代替）
   - setDisplayMode（モード切替）: 切替先モードのスクロール復元位置を設定（restoreFromPersistedPosition が消費するのは isSourceMode の変化時のみ）
   リネームでは読み直さない。ライブ値をそのまま引き継ぐ（表示モードが TASK-369 で同じ判断をしている）。
5. ライブ値の更新は JS からの通知（renderer(_:didChangeZoom:) / didChangeScrollPosition）で保存と同時に行う。TASK-270（窓生成が対象確定より先だと既定倍率で取り残される）を再発させないため、値の変化で SwiftUI 再評価が走る形は維持する。
6. 表示モードの窓間同期を撤去する。setDisplayMode 末尾の delegate 通知、ViewerWindowControllerDelegate.viewerWindow(_:didChangeDisplayMode:)、ViewerWindowManager.mirrorDisplayMode、ViewerWindowController.mirrorDisplayMode を削除。sourceToggleReturn のクリアは setDisplayMode 側に残る。
7. テスト:
   - ViewerWindowManagerDisplayModeSyncTests を「同期しないこと」を担保する形へ書き換える
   - 保存値を書いても生きている窓のライブ値が変わらないことを ViewerStore 上で検証する（AC#4。読み直し経路が復活したら落ちる）
   - WebViewCommandControllerTests の applyStoredZoom 依存を除去

【別タスクへ切り出す】renderer(_:didChangeScrollPosition:) は fileURL を都度参照するため、ファイル切替直後に遅れて届いた通知が切替先のキーへ切替前の位置を書きうる（設計レビュー項目 8）。本タスクの原因とは別系統のため別途起票する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

原因は task 起票時の記述（ViewerWindowController.swift:491 の再ロード時 applyStoredZoom）ではなかった。:491 の applyStoredZoom は performFileSwitch 内、つまりファイル切替の契機であり原則上は許容される側だった。

真の経路は SwiftUI 経由。ViewerContentView.currentZoom / currentScrollPosition が共有ストアを毎回の body 再評価で読み直す computed property で、窓 B が別要因（ライブリロード等）で再評価した瞬間に、窓 A が保存した値を拾って ViewerRenderer.initialPageZoom の didSet が即適用していた。ZoomStore は @Observable ではないため他窓の書き込み単独では発火しないが、再評価の契機は日常的に起きる。

## 設計レビュー（/review-design）の結論と反映

- 新しい @Observable 状態は導入しなかった。ADR が手本として挙げる ViewerStore.showLineNumbers と同じ場所（窓ごとの既存 @Observable である ViewerStore）へライブ値 zoom / scrollPositionToRestore を置いた。
- 担保は「テスト」だけでなく「構造」でも取った。ViewerContentView から zoomStore / scrollPositionStore の引数自体を撤去したため、渡らないから読めない。読み直し経路を戻すにはシグネチャを戻す必要がある。
- WebViewCommandController.applyStoredZoom() を撤去し、保存値の読み手を 2 箇所から 0 箇所（提示開始の明示呼び出しのみ）へ畳んだ。
- WebViewCommandController.init の onZoomChanged は既定値を持たせていない。直接 HTML モードは viewer.js が居らず JS からの通知が来ないため、渡し忘れると静かにライブ値が取り残される（ADR 0002 / TASK-319 と同じ型の事故を構造で防ぐ）。
- リネームでは保存値を読み直さない。表示モードが TASK-369 で同じ判断をしており、引き継ぐべきはライブ値。

## 保存値を読む契機（3 つに限定）

1. ViewerWindowController.init（オープン）→ beginPresentingDocument(at:)
2. performFileSwitch（ファイル切替）→ beginPresentingDocument(at:)
3. setDisplayMode（モード切替）→ 切替先モードのスクロール復元位置のみ

## 検証（実測）

- swift test: 1223 tests / 178 suites 全て成功（Integration 含む）
- xcodebuild build -scheme befold: BUILD SUCCEEDED
- swiftformat --lint: 0 files require formatting
- swiftlint: origin/main とのベースライン差分は、既存警告の行数の増減のみで新規違反ゼロ（行数を正規化した diff が空）

## UserDefaults キー

廃止・改名・意味の変更なし。ZoomStore / ScrollPositionStore のキーも粒度もそのままで、変えたのは「いつ読むか」だけ。移行は不要。

## 別タスクへ切り出した

TASK-400: renderer(_:didChangeScrollPosition:) が fileURL を都度参照するため、切替直後に遅れて届いた通知が切替先のキーへ切替前の位置を書きうる（設計レビュー項目 8）。

## 完了処理での実測（/finish-task 手順 2）

修正を一時的に戻して、新規テストが実際に落ちることを実測した（対象ファイルはスクラッチパッドへ退避して復元。git stash は使わない）。

### M1: 提示開始の読み込みを消す（init の beginPresentingDocument(at:) を削除）

落ちたテスト 3 件（ViewerWindowStateIndependenceTests）:

- 「閉じてから開き直すと、保存された倍率とスクロール位置から始まる」→ (store.zoom → 1.0) == 1.5 / (scrollPositionToRestore → 0.0) == 0.4
- 「保存倍率が他窓に書き換えられても、開いている窓のライブ倍率は動かない」
- 「保存スクロール位置が他窓に書き換えられても、開いている窓の復元位置は動かない」

### M2: 窓間同期を戻す（delegate 通知 + ViewerWindowManager.mirrorDisplayMode + ViewerWindowController.mirrorDisplayMode を復活）

落ちたテスト 3 件:

- 「同一ファイルを 2 窓で開いても、差分表示の選択は選んだ窓だけに効く」
- 「同一ファイルを 2 窓で開いても、ソース表示の選択は選んだ窓だけに効く」
- 「cmd+U の戻り先の記憶は窓ごとで、操作していない窓は既定のソース表示へ戻る」

### 空振りしていたテストを強化した

M1 の初回実測で、ライブ値の 2 テスト（倍率・スクロール位置）が**通ってしまった**。保存値が空の状態で窓を開き「既定値のまま」を確認していたため、「そもそも読んでいない」と「読み直していない」を区別できていなかった。提示開始で読む値（1.25 / 0.3）と、その後に他窓が書く値（1.75 / 0.6）を別にする形へ書き換え、両方の mutation で落ちることを確認した。

### 構造でしか担保できていない部分（テストでは検出できない）

元の不具合そのもの（ViewerContentView が body 再評価のたびに保存値を読む）は、この層のテストでは再現できない。テストのフィクスチャはコンテンツペインをプレースホルダに差し替えており、実 SwiftUI ビューを評価しないため。ここは ViewerContentView から ZoomStore / ScrollPositionStore の引数を撤去したこと（読み直しの復活にシグネチャ変更を要求する＝コンパイルで止まる）が担保になっている。

### 受け入れ条件の書き換え

起票時の AC#1 は「再ロードやファイル切替を挟んでも他窓の値を拾わない」だったが、ADR 0002 の決定ではファイル切替は提示開始であり保存値を読む（＝他窓が最後に書いた値を拾うのが正しい）。実装に合わせて AC を 5 件へ分割し、「読み直さない」と「提示開始では読む」を別条件にした。

### 再検証（テスト強化後）

- swift test: 1223 tests / 178 suites 全て成功
- swiftformat: 全ターゲットで整形差分なし
- swiftlint: origin/main とのベースライン差分ゼロ（新規違反なし）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
文書の状態（ズーム倍率・スクロール位置・表示モード）を窓ごとのライブ値優先へ変え、生きている窓が保存値を読み直す経路を塞いだ。ライブ値は新しい型を作らず既存の窓ごと @Observable である ViewerStore に置き（ADR が手本とする showLineNumbers と同じ場所）、ViewerContentView からは ZoomStore / ScrollPositionStore の引数自体を撤去して「渡らないから読めない」構造にした。保存値を読むのは提示開始の 3 契機（オープン・ファイル切替・モード切替）だけで、リネームではライブ値を引き継ぐ。表示モードの窓間同期（mirrorDisplayMode とデリゲート通知）は TASK-371 ごと撤去した。検証: swift test 1223 tests/178 suites 全成功、xcodebuild BUILD SUCCEEDED、swiftformat 0 files require formatting、swiftlint は origin/main とのベースライン差分で新規違反ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
