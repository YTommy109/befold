# /quality-loop 設計

## 背景・目的

実装が完了しPRを作る前に、任意のタイミングで手動実行する品質チェックループを作る。
狙いは2つ:

1. 現在の diff を、正しさ・簡潔性（`/code-review` 相当の観点）と
   `docs/dev/coding_rule.md` への準拠の両面でレビューし、指摘がなくなるまで
   自動で修正を繰り返す。
2. ループ収束後、規約違反として検出されたパターンを振り返り、
   `docs/dev/coding_rule.md` 自体を育てる（同種の低品質コードが将来生まれにくくする）。

<!-- constrained-by ./2026-07-08-quality-loop-design.md#既存コマンドとの関係 -->

## 既存コマンドとの関係

- `/code-review`・`/improve`: 単発のレビュー→改善。ループや規約文書の成長は行わない。
- `/check`: ビルド・テストの実行のみ。本設計の Verify ステップで流用する。
- `/quality-loop` はこれらを代替せず、PR前の任意実行タスクとして追加する新規コマンド。

## トリガー・スコープ

- **起動**: ユーザーが手動で `/quality-loop` を実行する（実装完了後、PR作成前を想定）。定期実行やcronは対象外。
- **レビュー対象**: 現在のブランチの `main` に対する diff（`git diff main...HEAD`）。フルファイルではなく diff のみをレビュー対象に渡す。

## 全体フロー

```
iteration = 1
├─ [Round 1] Review: Agent(model: opus)
│     入力: git diff main...HEAD, docs/dev/coding_rule.md
│     観点: 正しさ・簡潔性・効率性（/code-review 相当）+ coding_rule.md 準拠
│     出力: 指摘リスト。各指摘に種別タグを付与
│           - rule-violation（coding_rule.md 準拠違反）
│           - bug / simplification / efficiency（一般的な品質指摘）
│
├─ 指摘ゼロ? ─Yes→ [Final Confirmation] へ
│     No
│     ├─ [Fix] Agent(model: sonnet): 指摘全件（タグ問わず）を修正
│     ├─ [Verify] swift build / swift test / npx jest（/check の3ステップを流用）
│     │     失敗 → Fix をやり直す（イテレーションは消費しない）
│     └─ iteration += 1
│
├─ [Round 2, 3] Re-review: Agent(model: sonnet)
│     入力: 自分が直した diff、Round 1 の指摘リスト、coding_rule.md
│     内容: 直した箇所が指摘に対応できているか、新たな規約違反を生んでいないかの自己チェック
│     （Opus は使わない。機械的な確認作業のため）
│     指摘ゼロ? ─Yes→ [Final Confirmation] へ
│     No ─ iteration <= 3 ? → Fix→Verify→iteration+=1→Re-review を繰り返す
│           iteration > 3 ? → ループ中断。残指摘とここまでの修正差分をユーザーに提示し、続行可否を確認
│
└─ [Final Confirmation]（Round 1〜3のいずれかで指摘ゼロになった直後に1回だけ実行）
      Agent(model: opus): 最終 diff 全体を一度だけ見直す（見落とし防止のダブルチェック）
      指摘ゼロ → [Retrospective] へ
      指摘あり → 自動ループはせず、ユーザーに提示して再実行や手動修正を判断してもらう
```

- **Opus 呼び出しは最大3回に固定**: Round 1 Review・Final Confirmation・Retrospective。
  イテレーションが増えても（Round 2, 3 は Sonnet のため）Opus 呼び出しは増えない。
- **最大イテレーション数は3**。超過時は自動継続せず、必ずユーザーに判断を仰ぐ。

## Retrospective（coding_rule.md の成長）

- **実行タイミング**: Final Confirmation が指摘ゼロで終わった後（正常収束時のみ）。
  イテレーション上限で中断した場合は、ユーザーが続行を選ばなかった時点でスキップ可能。
- **入力**: 全ラウンドの指摘ログのうち `rule-violation` タグが付いたものだけ。
  `bug` / `simplification` などの一般指摘はルール化候補にしない。
- **処理**: Agent(model: opus) が、繰り返し発生した違反パターンや
  `coding_rule.md` に明文化されていなかった暗黙ルールを洗い出し、
  追記・修正の差分案（Markdown diff 形式）を作る。
- **反映方法**: 差分案をユーザーに提示 → 承認された場合のみ `docs/dev/coding_rule.md` を Edit で更新。
  自動追記はしない（誤った一般化がルールに紛れ込むのを防ぐため）。
- **コミット**: 別途ユーザーに確認してから行う（グローバル方針のコミット規約に従う）。

## 安全弁

- 最大イテレーション: 3（Round 2, 3 の Sonnet 再レビューが対象）。
- Verify（ビルド・テスト）失敗は必ず Fix のやり直しでゲートする。イテレーション超過とは独立してリトライする。
- 自動ループが人間の判断を必要とする分岐（イテレーション超過、Final Confirmation での新規指摘）では、
  常にユーザーに提示して止まる。無限ループ・暴走はしない。

## 成果物

- 新規スラッシュコマンド `.claude/commands/quality-loop.md`
  - `/improve` と同様、メインエージェントが Agent ツールでサブエージェント（Review/Fix/Re-review/Final Confirmation/Retrospective）を
    順にオーケストレーションする指示書形式。Workflow ツールは使わない（手動・セッション内完結のスケール感のため）。
- コマンド末尾に用途（実装完了後・PR作成前に手動実行）を明記。

## テスト・検証方針

- コマンド自体はエージェントオーケストレーションの指示書であり、自動テスト対象外
  （`/improve` などの既存コマンドと同様）。
- 導入後、実際の diff に対して1〜2回試験的に実行し、以下を確認する:
  - Review の指摘にタグが正しく付与されるか
  - Round 2, 3 の Sonnet 再レビューが Round 1 の指摘を正しく参照できるか
  - Final Confirmation・Retrospective が意図通り1回だけ実行されるか
  - イテレーション超過時にユーザーへの確認で正しく止まるか
