---
id: TASK-277
title: フォルダー表示中に VoiceOver が不可視の文書を読み上げないことを実機確認する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 01:32'
updated_date: '2026-08-05 14:19'
labels:
  - accessibility
  - bug
dependencies: []
priority: medium
ordinal: 467000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-271（ADR 0002 段 2）の受け入れ条件 #3 を分離したもの。実装・テストは TASK-271 で完了済みで、残るのは VoiceOver を実際に有効化しての確認だけ。

## 背景
WKWebView は AppKit/WebKit 側で独自のアクセシビリティ木を公開するため、SwiftUI の accessibilityHidden(true) が必ずしも刈り取らない。フォルダー一覧の表示中に VO カーソルが一覧を通り越して不可視の文書を読み上げる懸念がある。

## 実測済みの事実（TASK-271）
AX ツリー上はフォルダー提示中に web area が現れない（webAreas=0）。VoiceOver はこの木を辿るため到達しない見込み。ただし VoiceOver を実際に ON にしての確認は未実施（読み上げが始まり環境を占有するため）。

## 手順
1. dev ビルドを起動し、フォルダーを開く
2. Cmd+F5 で VoiceOver を有効化
3. VO カーソル（Ctrl+Option+矢印）でフォルダー一覧を端まで辿る
4. 不可視の文書の内容が読み上げられないことを確認

読み上げが起きた場合は、WebView 側の accessibilityElement 制御（NSView.setAccessibilityElement(false) 等）を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 VoiceOver を有効にした実機で、フォルダー表示中に VO カーソルが不可視の文書へ到達せず、その内容が読み上げられない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## VoiceOver 実機確認（2026-08-05, fix/appex, Debug ビルド 1.12.0/1219）

### 準備
befold を終了して開き直し（セッション復元で他ウィンドウも開くため、対象は window 1 = README.md のウィンドウ）、サイドバーで docs フォルダー行を AX 経由で選択。スクリーンショットで『サイドバー = docs 選択、右ペイン = フォルダー一覧（.. / adr / dev / superpowers / .nojekyll / index.html）、タイトル = README.md』のフォルダー提示状態を確認した。文書（README.md）は直前まで表示されていたため WebView は常駐かつ内容を保持している。

### AX ツリー（VoiceOver OFF・状態を固定して再計測）
| 状態 | 走査前後のタイトル | AXWebArea | AXOutline |
|---|---|---|---|
| ファイル（README.md）表示中 | README.md / README.md | 1 | - |
| フォルダー行（docs）選択中 | README.md / README.md | **0** | 2（サイドバー＋一覧） |

TASK-271 の webAreas=0 がこのブランチでも再現。

### VoiceOver ON での実測
VoiceOver.app を起動（Cmd+F5 は効かなかったため /System/Library/CoreServices/VoiceOver.app を直接起動）。VO カーソルの位置は各ステップのスクリーンショットで確認した。

1. 初期状態: VO カーソルはサイドバー（一覧）
2. Ctrl+Option+→ ×6: サイドバー → スプリッタ → 右ペイン（フォルダー一覧）と進み、**それ以上進まない**（web area も文書も列挙されない）
3. Ctrl+Option+Shift+↓ で右ペインへ入り、Ctrl+Option+→ ×8: 一覧の行（.. → adr → dev → superpowers → .nojekyll → index.html）を順に辿り、**最終行 index.html で停止**。不可視の文書へは到達せず、README の本文が読み上げ対象になることは一度も無かった

確認後 VoiceOver は OFF に戻した（pgrep で確認済み）。

### 補足（計測上の注意）
System Events による AX 全走査は 1 回あたり約 25 秒かかる。この間にウィンドウの選択が変わると、測った値がどの提示状態のものか特定できなくなる（実際に途中でセッション中の操作が入り、ファイル表示中の AXWebArea=1 をフォルダー提示中の値と取り違えかけた）。走査の前後でウィンドウタイトルを取り、変化していないことを確認する形にした。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
VoiceOver を実際に有効化した実機確認を行い、フォルダー表示中に VO カーソルが不可視の文書へ到達しないことを確認した。VO カーソルはサイドバー → スプリッタ → 右ペイン（フォルダー一覧）までしか進まず、一覧へ入って端まで辿っても最終行で停止し、README 本文が読み上げ対象になることは無かった。あわせて AX ツリー上もフォルダー提示中は AXWebArea=0（ファイル表示中は 1）であることを、走査前後のタイトル一致で状態のずれが無いことを確かめたうえで再計測した。確認後 VoiceOver は OFF に戻した。追加の実装変更は不要。
<!-- SECTION:FINAL_SUMMARY:END -->
