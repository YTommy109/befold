---
id: TASK-20
title: 検索バー起動時の全チャンク読み込みが上限・キャンセルなしで DOM を全量構築しフリーズを再導入する
status: Done
assignee: []
created_date: '2026-07-16 10:53'
updated_date: '2026-07-16 14:14'
labels:
  - obsolete
dependencies:
  - TASK-29
references:
  - BefoldApp/BefoldKit/Resources/viewer.html
  - BefoldApp/befold/Viewer/ViewerWebView.swift
  - docs/superpowers/specs/2026-07-14-line-chunked-loading-design.md
priority: high
type: bug
ordinal: 50
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コミット 108a436 により、切り詰め表示中に Cmd+F を押すと loadAllLinesForSearch → handleLoadMoreLines(untilFullyLoaded:true) が残り全チャンクを DOM に追記する。検索（_mmdFindRun）は DOM のテキストノード走査で実装されているため全量 DOM 化が必要になっているが、これはチャンク読み込み設計（docs/superpowers/specs/2026-07-14-line-chunked-loading-design.md）が「約 170 万セルの table はどのブラウザでも固まる」として排除した状態そのもの。行指向ファイルはサイズ上限なしで開けるため（ViewerStore.swift:234-246）、巨大 CSV で Cmd+F すると上限なし・キャンセル不可（find バーを閉じても Swift 側 while ループは止まらない、ViewerWebView.swift:447）で全量構築が走る。設計レベルの見直し候補: DOM ではなく蓄積済みテキストモデル（ViewerStore.content / JS _lastContent）を検索し、マッチ周辺のみ DOM 化する。最低限のハードニングとして untilFullyLoaded に行数/バイト上限と「読み込み済み範囲のみ検索」表示、find バー閉鎖時のキャンセルを入れる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 巨大な行指向ファイル（設計ドキュメントの 22MB/35k 行 CSV 相当）で Cmd+F を押しても WebView がフリーズしない
- [ ] #2 検索のための読み込みに上限またはキャンセル手段があり、上限時は検索範囲が明示される
- [ ] #3 設計判断（テキストモデル検索への移行 or 上限付き全量読み込み）が記録されている
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TASK-29(NormalizedTextCache刷新)のサブタスク29.6でloadAllLinesForSearch/untilFullyLoadedを廃止し、検索は表示済みDOM範囲のみを対象にする設計に変更済み(viewer.html _mmdOpenFind/_mmdFindRun、コミット8a014b1)。Cmd+Fで残チャンクを全量DOM化する経路自体が存在しなくなったため、本タスクの前提(上限・キャンセルなしの全量構築)は解消された。現行コードで loadAllLinesForSearch を grep しても該当箇所なしを確認。対応不要と判断し完了扱いにする。
<!-- SECTION:FINAL_SUMMARY:END -->
