---
id: TASK-701
title: CLI から行番号・アンカーを指定して開けるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-10-12 13:07'
updated_date: '2026-10-14 12:38'
labels:
  - cli
dependencies: []
priority: low
type: feature
ordinal: 890000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI は開く位置を指定できない。`befold file.md:42` や見出しアンカーで開く手段が無く、エディタ・grep 結果・エージェントの出力から直接該当箇所へ飛べない。CLIOpenOptions と CLIRequest に該当フィールドが無い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 行番号を指定して開くと、開いた後にその行へジャンプする（構文は `path:LINE` か `--line <n>` かを設計で決め、パスに : を含む場合の曖昧さを扱う）
- [x] #2 Markdown の見出しアンカー指定の要否を決め、採るなら実装、採らないなら理由を Notes に残す
- [x] #3 本体にジャンプ手段が既にあるか（rg "jumpTo" BefoldApp/befold）を先に確認し、あれば再利用する
- [x] #4 CLIRequestWire のテストと README/cli-launch.md の更新
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLI: --line <n>（path:LINE と見出しアンカーは不採用）。validate: 1 以上・パス 1 つ・--preview/--diff 併用不可、表示モード未指定は source に
2. ワイヤ: CLIOpenOptions.line: Int?（旧 JSON 互換）
3. 本体: CLIDisplayOverrides に束ね、ViewerStore.revealLineRequest(LineRevealRequest, 通し番号) → ViewerRenderer.reveal が一度だけ配達 → JS reveal-line.ts が文書パスつきで保留し描画/追記/読み込み状態で試す
4. テスト: validation / wire / bridge script / 配達の一度きり / jest(保留・段階読み込み・順序)
5. 実機確認（新規窓・既存窓・未読み込み領域・末尾超え）と docs
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
未確認: 本体側の既存ジャンプ経路の有無。着手前に /review-design を回す。

/review-design 相当の判断: (1) 本体の既存ジャンプは前/次の相対移動のみ(ViewerJumpBridge)で絶対行ジャンプは無いため新設。(2) path:LINE は ':' を含むファイル名との曖昧さの解消に実 FS 参照が要り、得るのは入力短縮だけなので不採用。見出しアンカーはレンダリング表示に行と DOM の対応が無く、行番号で足りるので不採用。(3) 実機で発見した不具合: Swift は _mmdSetTruncated(false) を最後のチャンクの追記より先に送るため、依頼中の非切り詰め通知で確定すると 2000 行目止まりになった（--line 2500）。非切り詰め時の行数は TruncationState が 0 に正規化するので行数は判断に使えない。依頼中は追記を待ち、待機中の再描画では要求を捨てる。jest に実際の順序の回帰テストを追加。実機: --line 2500(新規窓)=2500 が先頭、--line 100(既存窓)=100、--line 9999=末尾。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
--line <n> を追加(ソース表示で n 行目を先頭へ。1 パスのみ、--preview/--diff 併用不可、モード未指定は source)。本体は既存の相対ジャンプを流用せず、LineRevealRequest(通し番号)→ViewerRenderer.reveal→viewer-src/reveal-line.ts で文書パスつきに保留し、段階読み込みの続きを待って満たす。path:LINE と見出しアンカーは理由を Notes に残して不採用。swift test 2048+83 件・jest 705 件 pass、実機で新規窓/既存窓/未読み込み領域/末尾超えを確認。README ja/en・cli-launch.md・site 更新。
<!-- SECTION:FINAL_SUMMARY:END -->
