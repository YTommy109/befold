---
id: TASK-394
title: ファイル切替の素早い往復で非同期保存が届く前の古いスクロール位置を復元する
status: Done
assignee: []
created_date: '2026-08-09 13:33'
updated_date: '2026-08-09 22:00'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 653000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の PLAUSIBLE 指摘。

`beginPresentingDocument` は performFileSwitch 時に保存スクロール位置を **同期的に** 読むが、切替元の位置保存（saveScrollPositionBeforeTransition）は WKWebView の JS ラウンドトリップを介した **非同期** 書き込み。ファイル A をスクロール → A→B → 即座に B→A と往復すると、A の新しい位置の書き込みコールバックより先に `restoredScrollPosition(for: A)` が実行され、古い位置を復元する。`store.scrollPositionToRestore` は提示開始の 3 契機でしか設定されないため、遅れて完了した保存が拾い直されることもない。

参照: ViewerWindowController.swift:489 付近、WebViewCommandController.swift:113-116、WebViewDocumentRenderer.swift:82-84

発生窓は狭い（JS ラウンドトリップ 1 回分）ため優先度は低。修正するなら「保存完了を待ってから切替する」か「切替先の読み直しを保存完了後に行う」のいずれかで、TASK-393 の構造検討と合わせて判断するのがよい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A→B→A の素早い往復でも、A で最後にスクロールした位置が復元される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
単純化の検討: 値そのものが JS ラウンドトリップ経由でしか得られないため、「読む側を同期のまま速くする」道は無い。performFileSwitch 全体の非同期化は呼び出し元(switchFile / 履歴適用 / リンク遷移)と戻り値 FileSwitchOutcome へ波及するので採らない。新しい保留状態(辞書)も増やさない。

方針: 退場側の保存が完了した時点で、その値を「いま提示中の文書・モードと一致する場合だけ」ライブ復元値へ反映する。
1. WebViewCommandController.saveCurrentScrollPosition の completion で、保存した (position, url, mode) を窓へ通知する。通知は init の必須引数 onScrollPositionSaved で受ける(デフォルト引数を作らない = 渡し忘れがコンパイルエラー。DiffDisplayPreference / onZoomChanged と同じ形)
2. ViewerWindowController 側は、通知の (url, mode) が現在の (fileURL, 表示モード) と一致するときだけ store.scrollPositionToRestore を通知の値で更新する
3. **ストアから読み直さない**。ADR 0002 の規則 1 が禁じているのは保存値の読み直し(他窓の操作が後から効く)であり、ここで使うのは自窓が今書いた値そのもの。値を引数で運ぶ形にして、読み直しへ退化しないようにする
4. テスト: 遅延コールバック可能な FakeDocumentRenderer で A→B→A の往復を再現し、遅れて完了した A の保存が復元値へ反映されること / 一致しない場合(B へ切替済み)は反映されないことを検証
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
設計判断: ADR 0002「保存値を読むのは提示開始時だけ」との関係を確認した。この修正は保存値ストアを読み直さず、自窓が発行した保存の値を引数で受け取って使うため、規則 1 の趣旨(他窓の操作が後から効くのを防ぐ)に反しない。値をストアから引き直す実装にすると規則違反になるので、コールバックは値を引数で運ぶ形に固定する。
既知の限界: 保存完了が切替先の applyRender より後に届いた場合、復元値は正しく直るが画面への再注入は行わない(位置だけを後から動かすと、ユーザーが既にスクロールし始めていた場合に勝手に飛ぶため)。発生窓はさらに狭い。

実装: WebViewCommandController.saveCurrentScrollPosition の completion で、保存した (position, url, mode) を必須引数 onScrollPositionSaved で窓へ通知する。ViewerWindowController.applySavedScrollPositionToLiveValue が、その (url, mode) が現在の (fileURL, 表示モード) と一致するときだけ store.scrollPositionToRestore を通知の値で更新する。保存値ストアからは読み直さない(ADR 0002 規則 1 との整合。値を引数で運ぶ形に固定)。
テスト差し替え口: ViewerWindowController.init に documentRenderer(既定 nil = 本番の WebViewDocumentRenderer)を追加し、Fixture から注入できるようにした。JS ラウンドトリップの完了タイミングを制御するため。

検証:
- AC1 = ViewerWindowScrollRestoreRaceTests「A→B→A の往復中に完了した A の保存が、A のライブ復元値へ追いつく」。保留した保存を任意の時点で完了させる DeferredScrollRenderer で往復を再現し、往復直後は復元値 0(古い値)、保存完了後に 640 になることを確認。
- トリップワイヤ確認: applySavedScrollPositionToLiveValue の代入を一時的に無効化して同テストを実行し、実際に落ちること(Expectation failed: 0.0 == 640.0)を確認済み。空振りしていない。
- 対称ケース: 「いま提示していない文書の保存が完了しても、ライブ復元値は動かさない」で、B に居る間に届いた A の保存が B の復元値を汚さないことを固定。
- WebViewCommandController 層: 「保存が完了したら、保存したキーと値を窓へ伝える」(取得できなければ通知しない / キーと値がそのまま渡る)。
- swift test 1241 件パス(--no-parallel)。jest 391 件パス。swiftlint は origin/main 比で新規違反ゼロ(3 要素タプルの large_tuple を struct 化して解消、ViewerWindowController の file_length 超過は Presentation State / Capabilities extension を別ファイルへ分離して回避)。

既知の限界(未対応): 保存完了が切替先の applyRender より後に届いた場合、復元値は正しく直るが画面への再注入は行わない。位置だけを後から動かすと、ユーザーが既にスクロールし始めていた場合に勝手に飛ぶため。発生窓は元の窓よりさらに狭い。

環境メモ: フル並列の swift test で ViewerRendererZoomIntegrationTests / ViewerRendererContentUpdateIntegrationTests が 60 秒タイムアウトする事象に遭遇したが、同スイート単独では 0.26 秒で通り、--no-parallel の全件実行も通る。実 WKWebView の同時生成によるリソース競合(WebKit の子プロセスが 25〜29 個残留)であり、本変更とは無関係。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
退場側のスクロール位置保存(JS ラウンドトリップ経由で非同期)が完了した時点で、そのキーがいま提示中の文書と一致していればライブな復元値へ追いつかせるようにした。A→B→A の素早い往復で古い位置を復元する問題が解消する。保存値ストアは読み直さず、保存した値を引数で受け取る形にして ADR 0002 の規則 1 と両立させた。回帰テストは修正を外すと落ちることを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
