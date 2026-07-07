# /quality-loop — 規約準拠・品質ループ

実装が完了し PR を作る前に手動実行する品質チェックループです。
現在のブランチの diff を対象に、正しさ・簡潔性のレビューと
`docs/dev/coding_rule.md` への準拠チェックを行い、指摘がなくなるまで
Agent ツールで自動修正を繰り返します。収束後は `docs/dev/coding_rule.md`
自体の改善提案（Retrospective）まで行います。

以下のワークフローを順に実行してください。

## 対象範囲

`git diff main...HEAD` を対象にする。個別ファイルの全文ではなく diff のみを
各サブエージェントに渡すこと。

## ワークフロー

イテレーション番号はラウンド番号と同一に扱う: Round 1 の Review が
iteration=1、Round 2 の Re-review が iteration=2、Round 3 の Re-review が
iteration=3。Round 4 は存在しない。

### Round 1: Review（Opus）

Agent ツールを `model: "opus"` で1件起動し、以下を渡す:

- `git diff main...HEAD` の出力
- `docs/dev/coding_rule.md` の全文

観点は2つ:
1. 正しさ・簡潔性・効率性（`/code-review` 相当の一般的な品質観点）
2. `docs/dev/coding_rule.md` の各項目への準拠

出力は指摘リスト。各指摘に以下を含めること:
- 種別タグ: `rule-violation`（coding_rule.md 準拠違反）/ `bug` / `simplification` / `efficiency` のいずれか
- ファイルパス・行番号
- 指摘理由
- 修正方針

指摘ゼロなら Round 1 の修正はスキップし、直接「Final Confirmation」に進む。

### Fix（Sonnet）

Round 1（または直近の Re-review）の指摘が1件以上ある場合、Agent ツールを
`model: "sonnet"` で1件起動し、指摘リスト全件（タグ問わず）を修正させる。
指摘にない範囲は変更しないこと。

### Verify

修正のたびに以下を実行する（`/check` の手順を流用）:

```bash
cd BefoldApp && swift build
cd BefoldApp && swift test
cd BefoldApp && [ -d node_modules ] || npm ci
cd BefoldApp && npx jest
```

いずれか失敗した場合は Fix をやり直す。この再試行はイテレーション数を
消費しないが、同一ラウンド内で2回までとする。2回リトライしても Verify が
失敗する場合は自動ループを中断し、ビルド・テストの失敗内容と現在の diff を
ユーザーに提示して手動対応を仰ぐ。

### Round 2, 3: Re-review（Sonnet 自己チェック）

Fix + Verify が成功したら、Agent ツールを `model: "sonnet"` で1件起動し、
以下を渡す:

- 直前の Fix で変更した diff
- Round 1 の指摘リスト（元の指摘）
- `docs/dev/coding_rule.md` の全文

「元の指摘に対応できているか」「新たな規約違反を生んでいないか」を
自己チェックさせる。出力形式は Round 1 の Review と同じ（種別タグ付き指摘リスト）。
このラウンドは Opus を使わないこと。

指摘ゼロなら「Final Confirmation」に進む。指摘が残る場合:
- 現在のラウンドが Round 2（iteration=2）なら、Fix → Verify のあと
  Round 3（iteration=3）の Re-review を実行する
- 現在のラウンドが Round 3（iteration=3）なら、これが最大イテレーションの
  ため Round 4 は実行しない。自動ループを中断し、残指摘とここまでの
  修正差分をユーザーに提示して、続行するか手動対応に切り替えるかを確認する

### Final Confirmation（Opus、1回のみ）

Round 1〜3 のいずれかで指摘ゼロになった直後に一度だけ、Agent ツールを
`model: "opus"` で起動し、最終的な diff 全体（コマンド開始時からの累積差分）
を見直させる。見落とし防止のダブルチェックであり、新規の指摘があれば
種別タグ付きで報告させる。

- 指摘ゼロ → 「Retrospective」に進む
- 指摘あり → 自動ループはせず、指摘内容をユーザーに提示し、再度
  `/quality-loop` を実行するか手動で対応するかを確認する

### Retrospective（Opus、1回のみ）

Final Confirmation が指摘ゼロで終わった場合のみ実行する。ただし、これまでの
全ラウンドで収集した rule-violation タグの指摘が1件もない場合、Retrospective
はスキップする。

これまでの全ラウンドで出た指摘のうち `rule-violation` タグが付いたものだけを
集約し、Agent ツールを `model: "opus"` で1件起動する。渡す内容:

- 集約した `rule-violation` タグの指摘一覧（種別・ファイル・理由・修正方針）
- `docs/dev/coding_rule.md` の全文

依頼内容: 繰り返し発生した違反パターンや、`coding_rule.md` に明文化されて
いなかった暗黙のルールを洗い出し、`docs/dev/coding_rule.md` への追記・修正を
Markdown diff 形式の提案として作成する。

出力された差分案をユーザーに提示する。ユーザーが承認した場合のみ
`docs/dev/coding_rule.md` を Edit で更新する。自動追記はしない。
コミットするかどうかは別途ユーザーに確認する。

## 安全弁

- 最大イテレーション数: 3（Round 1 の Review が iteration=1、Round 2/3 の
  Re-review が iteration=2/3 に対応。Round 4 は存在しない）
- Verify 失敗は必ず Fix のやり直しでゲートする（イテレーション数は消費
  しない）。ただし同一ラウンド内で2回までとし、2回失敗したら自動ループを
  中断してユーザーに提示する
- Round 3（iteration=3）で指摘が残った場合、または Final Confirmation で
  新規指摘が出た場合は、自動継続せず必ずユーザーに提示して判断を仰ぐ
- rule-violation タグの指摘が1件もない場合、Retrospective はスキップする
