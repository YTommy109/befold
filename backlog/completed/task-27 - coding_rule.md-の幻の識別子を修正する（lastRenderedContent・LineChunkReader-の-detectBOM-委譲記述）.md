---
id: TASK-27
title: >-
  coding_rule.md の幻の識別子を修正する（lastRenderedContent・LineChunkReader の detectBOM
  委譲記述）
status: Done
assignee: []
created_date: '2026-07-16 10:55'
updated_date: '2026-07-17 01:33'
labels: []
dependencies: []
references:
  - docs/dev/coding_rule.md
priority: low
ordinal: 120
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
今回の差分（8ef7703, c3189f5）でコードが変わったのに docs/dev/coding_rule.md が追随していない箇所が 2 つある。(1) 321 行目「コンテンツ差分チェック（lastRenderedContent）で不要な再描画を防ぐ」— lastRenderedContent は 8ef7703 で削除済み（現在は lastRenderedContentRevision、grep で BefoldApp 内に残存なし）。(2) 233 行目の単一情報源テーブル「LineChunkReader は detectBOM / detectEncoding / trimIncompleteUTF8Tail に委譲」— c3189f5 で LineChunkReader は detectEncoding のみ呼ぶ形に統合済み（detectBOM 直接呼び出しなし）。隣接する 232 行目「decodeText と isChunkableEncoding の双方がここに委譲」も decodeText が detectEncoding 経由になったため要確認。同差分内で fd44a46 が同種の幻識別子（ViewerStore.decodeFullFile）を直しており、coding_rule.md 自身が定める「同一 diff 内の自己整合性」ルールに照らして残りも修正する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 coding_rule.md に実在しない識別子 lastRenderedContent への言及がない
- [x] #2 単一情報源テーブルの LineChunkReader / decodeText の委譲記述が現行実装と一致している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査の結果、記載時点よりコードがさらに進み LineChunkReader は 68d1d75 で削除され StringChunkReader（NormalizedTextCache 経由の復号済みテキストを読むのみ）に置き換わっていた。isChunkableEncoding も現存しない。単純化の余地は無く（コードの構造自体は既に単一情報源に集約済み）、ドキュメントを現行実装に追随させるだけで足りると判断。coding_rule.md の 321行目 lastRenderedContent→lastRenderedContentRevision、232-233行目の単一情報源テーブル（BOM検出/テキスト復号の委譲記述）を修正。加えて同ファイル61行目のプロジェクト構成コメントにも LineChunkReader の幻の識別子が残っていたため StringChunkReader に修正、および .claude/CLAUDE.md 内の同一箇所も同様に修正（同一 diff 内の自己整合性ルールに基づく波及修正）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
docs/dev/coding_rule.md の幻の識別子2箇所を現行実装に合わせて修正。321行目: lastRenderedContent→lastRenderedContentRevision（grepで実在確認）。232-233行目の単一情報源テーブル: LineChunkReader は 68d1d75 で削除済みのため後継 StringChunkReader（NormalizedTextCache 経由の復号済みテキストを読むのみ）に、isChunkableEncoding は現存しないため DefaultFileReader.isBinary に、それぞれ実際の委譲関係へ更新。同一 diff 内の自己整合性ルールに基づき、同ファイル61行目のプロジェクト構成コメント、および .claude/CLAUDE.md 内の同一箇所にも残っていた LineChunkReader の幻の識別子を StringChunkReader へ波及修正。修正後 grep で全ての幻の識別子が0件になったことを確認。単純化検討: ドキュメント修正であり実装コードの単純化余地はなし（コード自体は既に TextEncoding への単一情報源集約が完了済み）。
<!-- SECTION:FINAL_SUMMARY:END -->
