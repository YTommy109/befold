---
id: TASK-27
title: >-
  coding_rule.md の幻の識別子を修正する（lastRenderedContent・LineChunkReader の detectBOM
  委譲記述）
status: To Do
assignee: []
created_date: '2026-07-16 10:55'
labels: []
dependencies: []
references:
  - docs/dev/coding_rule.md
priority: low
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
今回の差分（8ef7703, c3189f5）でコードが変わったのに docs/dev/coding_rule.md が追随していない箇所が 2 つある。(1) 321 行目「コンテンツ差分チェック（lastRenderedContent）で不要な再描画を防ぐ」— lastRenderedContent は 8ef7703 で削除済み（現在は lastRenderedContentRevision、grep で BefoldApp 内に残存なし）。(2) 233 行目の単一情報源テーブル「LineChunkReader は detectBOM / detectEncoding / trimIncompleteUTF8Tail に委譲」— c3189f5 で LineChunkReader は detectEncoding のみ呼ぶ形に統合済み（detectBOM 直接呼び出しなし）。隣接する 232 行目「decodeText と isChunkableEncoding の双方がここに委譲」も decodeText が detectEncoding 経由になったため要確認。同差分内で fd44a46 が同種の幻識別子（ViewerStore.decodeFullFile）を直しており、coding_rule.md 自身が定める「同一 diff 内の自己整合性」ルールに照らして残りも修正する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 coding_rule.md に実在しない識別子 lastRenderedContent への言及がない
- [ ] #2 単一情報源テーブルの LineChunkReader / decodeText の委譲記述が現行実装と一致している
<!-- AC:END -->
