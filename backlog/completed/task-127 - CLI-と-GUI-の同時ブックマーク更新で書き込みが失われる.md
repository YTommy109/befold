---
id: TASK-127
title: CLI と GUI の同時ブックマーク更新で書き込みが失われる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:22'
updated_date: '2026-07-25 04:05'
labels:
  - cli
  - bug
dependencies: []
priority: medium
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で PLAUSIBLE 判定。befold-cli/BefoldCLICommand.swift:88 で CLI の bookmarkStore は GUI と同じ UserDefaults ドメイン(com.degino.befold)に別プロセスから書き込む。BookmarkStore.add/toggle は BookmarkedPaths 配列全体の非アトミックな read-modify-write のため、CLI の `befold --bookmark a.md` と GUI のブックマーク操作がほぼ同時に走ると、GUI が CLI 追加前の配列を書き戻して追加分を消す(CLI は成功を報告済みなのにブックマークが消えるデータロス)。
対応方針は要検討: 書き込みを GUI プロセスへ転送して一本化する、通知で GUI に再読込させる、等。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLI からのブックマーク追加が GUI の同時操作で失われない設計になっている
- [x] #2 採用した方式の並行性テストまたは設計メモがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIInstanceRouter のワイヤ表現に要求種別を導入する: decode(userInfo:) の戻りを CLIRequest 列挙(.open(paths:options:) / .bookmark(paths:))に変え、bookmark 用に forwardBookmark(paths:to:) を追加する(post + ACK 待ちループは open と共通化。bookmark では前面化しない)。
2. AppDelegate.handleCLIOpenRequest を CLIRequest による switch に変え、.bookmark では bookmarkStore.add のみ行う(NSApp.activate しない)。ACK と重複排除は既存経路をそのまま使う。
3. befold-cli に CLIBookmarkRouter を追加する: 起動中インスタンスがあれば forwardBookmark、無ければ CLI プロセスが直接 BookmarkStore へ書く。転送失敗時は直接書きにフォールバックせず失敗を返す(CLIAppLauncher と同じ方針。フォールバックすると競合が復活するため)。
4. CLIBookmarkCommand.run の addBookmark を Bool 返しにし、失敗時は転送失敗メッセージ + exitCode 1 にする。BefoldCLICommand.run を CLIBookmarkRouter 経由に差し替える。
5. テスト: decode の種別分岐、forwardBookmark の再送/ACK/前面化しないこと、CLIBookmarkRouter の 3 分岐(起動中→転送のみ・転送失敗→ローカル書き込みなしで失敗・未起動→ローカル書き込み)、CLIBookmarkCommand の Bool 対応。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
起動中インスタンスがあるときは CLI ではなく GUI プロセスがブックマークを書くようにし、writer を常に 1 つに保った(CLIBookmarkRouter)。転送は既存の openRequest 通知に bookmarkPaths 種別を足す形で相乗りし、ACK・requestID による重複排除・再送はそのまま再利用している。転送不達時はローカル書き込みへフォールバックせず exit 1(遅れて届いた要求を GUI が処理すると二重書き込みになり競合が復活するため。CLIAppLauncher の転送失敗時の方針と同じ)。副作用として、GUI がコールドローンチ中で 10 秒以内に ACK を返せない場合の --bookmark は従来のローカル書き込みではなく失敗になる。検証: swift test 630 tests passed(CLIBookmarkRouterTests の 3 分岐・forwardBookmark の post/再送/ACK・decode の種別分岐を含む)。実 GUI を起動しての手動 e2e は未実施。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI と GUI の同時ブックマーク更新で片方の追加が消える競合を、書き込みプロセスを一本化することで解消した。起動中の befold.app があれば CLI は既存の CLIInstanceRouter 経路(bookmarkPaths 種別を追加)で追加要求を GUI へ転送し、GUI だけが UserDefaults を read-modify-write する。起動中インスタンスが無ければ writer は CLI のみなので従来どおり直接書く。転送不達時はフォールバックせず失敗を報告する。検証は swift test(630 tests passed)で、CLIBookmarkRouter の 3 分岐・forwardBookmark の再送/ACK・decode の要求種別分岐を新規テストで固定した。
<!-- SECTION:FINAL_SUMMARY:END -->
