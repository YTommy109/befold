---
id: TASK-485.19.2
title: バーのDOM/CSSを1つに統合しモード切替スイッチを追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-21 09:12'
updated_date: '2026-08-21 13:00'
labels: []
dependencies:
  - TASK-485.19.1
parent_task_id: TASK-485.19
priority: high
ordinal: 776000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
viewer.html の #mmd-find-bar / #mmd-jump-bar を単一の #mmd-bar コンテナへ再構成し、
モード切替スイッチ（検索/見出し/変更箇所）を追加する。このサブタスクでは見た目と
スイッチのクリックで表示領域が切り替わることまでを対象とし、検索・ジャンプの
既存ロジック（find.ts / jump.ts）への結線は次のサブタスクで行う。

対象:
- viewer.html:43-78 の #mmd-find-bar / #mmd-jump-bar 統合
- style.css:644-654 の .mmd-find-toggles 絶対配置前提の見直し
  （入力欄を持たないモードと同居させても崩れないレイアウトにする）
- モードごとの固有入力領域だけを差し替える
  （検索: 入力欄+Aa/ab|/.*トグル、見出し: レベルトグル、変更箇所: なし）
- 件数表示・前へ/次へ・閉じるは共通のまま
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 検索/見出し/変更箇所を切り替えるモード切替スイッチが1つのバーに存在する
- [x] #2 モードごとに固有の入力領域だけが表示され、共通要素（件数・前後・close）は1つを共有する
- [ ] #3 見た目の統合によりレイアウト崩れが無いことを実機確認している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DOM構造: #mmd-bar(外枠、bar.tsが表示/非表示を一元管理) > .mmd-bar-modes(検索/見出し/変更箇所の切替スイッチ、新設 bar-mode.ts) + #mmd-find-panel + #mmd-jump-panel(旧#mmd-find-bar/#mmd-jump-barを改名、中身と内部ID(mmd-find-*/mmd-jump-*)はfind.ts/jump.tsとも既存のまま変更なし)。bar.tsにonBarChangeフックを追加し、jump内のkind切替(見出し⇔変更箇所)もスイッチのハイライトに反映されるようにした(jump.ts open()末尾でupdateOuterVisibility()を明示呼び出し)。検証: npm test 556/556通過(新規viewer-main-bar-mode.test.js 6件含む)、typecheck/build/cycle-checkいずれも新規エラーなし。native-app-design.mdへの反映はTASK-485.19全体が完了するTASK-485.19.5でまとめて行う(19.1のNotesと同じ判断)。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-08-21 11:18
---
AC3（実機でのレイアウト確認）は今回チェックしていません。デバッグビルドを起動してスクリーンショットで確認しようとしましたが、System Events でのプロセスID指定によるウィンドウ取得が信頼できない状態（自分が起動したプロセスのウィンドウ数が0と返る／別プロセスへ操作が漏れる）で、実際に別ウィンドウ（無関係な実務ファイル）を誤って撮影する事故が1回発生しました（該当画像は即削除済み）。再発リスクを避けるため自動スクリーンショットでの確認を断念しました。お手すきの際に /run でデバッグビルドを起動し、⌘Fでバーを開いて検索/見出し/変更箇所のモード切替スイッチのレイアウトを目視確認していただけると助かります。
---

author: @claude
created: 2026-08-21 13:00
---
ユーザーによる実機での目視・操作確認により、2件の不具合が見つかり修正しました。(1) モード切替スイッチが左寄せのため、検索モード(幅広)に切り替わるとバー全体の左端が動いてボタン位置がズレる問題。.mmd-bar-modesをjustify-content:flex-endへ変更し、右端(right:12px固定)基準にして解決。(2) より重大な問題として、_mmdInitJump()内に本タスクでのリネーム(#mmd-jump-bar → #mmd-jump-panel)に追随し忘れた古いID参照が1箇所残っており(jump.ts:350)、document.getElementById('mmd-jump-bar')がnullを返してwireBarControlsが一度も呼ばれず、見出し/変更箇所モードの前へ・次へ・閉じるボタンが完全に無反応になっていた。Enter/Shift+Enterは別経路(keyboard.ts)で動くため気づけず、既存テストも実際のボタン要素へのclick()を一度も検証していなかった(next()/prev()の直接呼び出しかEnterキーのみ確認)。この2件を修正し、click()を直接シミュレートする回帰テストをfind/jump両方に追加した(修正前に戻すと実際に落ちることを実測)。
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
検索バー(#mmd-find-bar)とジャンプバー(#mmd-jump-bar)を単一の#mmd-barへ統合し、検索/見出し/変更箇所を切り替えるモード切替スイッチ(bar-mode.ts)を追加した。find.ts/jump.tsの内部ロジックは変更せず、パネルのコンテナIDのみ変更(結線の実体は次サブタスクで扱う想定どおり)。npm test 556/556通過で検証。実機でのレイアウト目視確認は自動化の信頼性問題により未実施(--commentに詳細)。
<!-- SECTION:FINAL_SUMMARY:END -->
