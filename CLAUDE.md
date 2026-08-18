## Issue Tracking の使い分け

- **ユーザー向けのバグ・要望**: GitHub Issues で管理する（ユーザーが体験する不具合や機能要望、外部からの報告）
- **実装都合・CI・リファクタ等の内部タスク**: backlog.md で管理する（設計判断やハンドオフが必要な内部作業。詳細は下記 Backlog.md Workflow を参照）

判断に迷う場合は「ユーザーの視点で報告される事柄か」を基準にする。ユーザーが直接遭遇する問題や要望は GitHub Issues、開発側の都合で発生する作業は backlog.md とする。

ただし現時点では、次に当てはまるものは GitHub Issues ではなく backlog.md でよい。

- 利用者が実質的に作者のみである現状で、外部に見せるより手元で回すほうが早いもの

公開済み機能で、かつ外部の利用者が遭遇しうるものは従来どおり GitHub Issues とする。

## 自律的なタスク進行のための運用ルール

- **着手不可なタスク**: 外部要因（レビュー待ち、他タスクの完了待ち、仕様未確定など）で着手できない場合は、`backlog task edit --append-notes` で「何が解消すれば着手できるか」を明記する。理由が書かれていれば、次回セッションでその要因が解消したかどうかを自分で判断して再開できる。
- **次に着手すべきタスクが自明でない場合**: 優先順位は次の基準で判断する。
  1. ユーザー向けの不具合（GitHub Issues）が未対応なら最優先
  2. 着手可能な backlog タスクのうち、他の作業をブロックしているもの
  3. 着手可能な backlog タスクのうち、着手順（登録順・依存関係）が早いもの
  この基準で決められない場合のみユーザーに確認する。
- **Notes に否定的な結論が記録されたタスク**: 「実施非推奨」「前提が誤り」等が実測付きで記録されているタスクの着手を指示された場合、記載どおりに実装せず、着手前に方針（縮小版で実施 / 記載どおり実施 / 見送り）をユーザーに確認する。Notes の記録は前回の調査結果であり、起票時の Description より新しい判断であることが多い。方針が決まったら、実態に合わなくなった Acceptance Criteria も `backlog task edit --acceptance-criteria` で書き換える。
- **着手順は ordinal で表現しない（表示順を制御できない）**: `backlog task edit --ordinal` を調整しても、コンソールの表示順は変わらない。実測（backlog CLI 1.50.1、2026-08-18）: `backlog task list --plain` は priority の降順→ID 順で並び、ordinal を見ていない（TASK-485.7 を ordinal 714800、TASK-485.6 を 740000 にしても 485.6 が先に出た）。`backlog board` は親タスクごとにサブタスクをぶら下げて表示し、その並びは ordinal 順でも ID 順でもない（規則は特定できていない）。**「HIGH が上に来るよう ordinal を調整する」という運用は成立しないので行わない。**
  - **重要度は priority で表す。** `task list` は priority で並ぶので、これは表示に効く唯一の手段。
  - **着手順の制約は依存で表す。** 「A を先に片付けないと B が二度手間になる」形の順序は `backlog task edit B --dep A` で構造にする。依存なら表示順に左右されず、次のセッションが順序を復元できる（実績: TASK-485.4 --dep TASK-485.7。kind 別 capability の穴を残したまま 3 つ目のジャンプ対象を足すと、新しい kind が同じ穴を継承するため）。
  - ordinal 自体は残っているが、この運用では使わない。
- **タスク ID の採番**: `backlog/config.yml` で `check_active_branches: true` / `remote_operations: true` が有効なため、`backlog task create` は他ブランチ上のタスクも含めて次の ID を採番する。ローカルのファイル一覧より大きい ID が振られるのは正常な動作であり、衝突回避のための ID 手動指定やファイルリネームは不要。
- **タスクファイルは git 管理対象**: `backlog/tasks/*.md` はリポジトリに含まれる。起票・更新・完了処理を行ったら、その場でコミットする。`backlog` CLI はファイルを書くだけで git 操作はしないため、未コミットのまま取り残されやすい（`/pr` の直前に `git status` で確認する）。どの PR に載せるかは次で判断する。
  - **実装を伴う起票・更新・完了処理**: その実装と同じ PR に含める（タスクの状態変化と実装が 1 つの単位でレビューされる）
  - **実装を伴わない起票のみ**: backlog（および ADR 等の関連ドキュメント）だけの PR にしてよい。実装ブランチを立てるまで手元に溜め込まない。実績: PR #448「chore: TASK-376 を起票する」
  - どちらの形でも、**起票のみのコミットは実装コミットと分ける**。実装 PR の中に起票コミットが混ざるのは許容する（実績: PR #447 に起票のみのコミット 3 件）が、1 つのコミットに起票と実装を同居させない

<!-- BACKLOG.MD GUIDELINES START -->
<!-- backlog.md-instructions-version: 1.48.0 -->
<CRITICAL_INSTRUCTION>

## Backlog.md Workflow

This project uses Backlog.md for task and project management.

**For every user request in this project, run `backlog instructions overview` before answering or taking action.**

Use the overview to decide whether to search, read, create, or update Backlog tasks.

Before task lifecycle actions, read the matching detailed guide:

- `backlog instructions task-creation` before creating or splitting tasks
- `backlog instructions task-execution` before planning, changing status or assignee, adding a plan or implementation notes, or implementing task work
- `backlog instructions task-finalization` before checking acceptance criteria, writing final summaries, or moving tasks to terminal statuses

Use `backlog <command> --help` before running unfamiliar commands. Help shows options, fields, and examples.

Do not edit Backlog task, draft, document, decision, or milestone markdown files directly. Use the `backlog` CLI so metadata, relationships, and history stay consistent.

</CRITICAL_INSTRUCTION>
<!-- BACKLOG.MD GUIDELINES END -->
