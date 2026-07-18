## Issue Tracking の使い分け

- **ユーザー向けのバグ・要望**: GitHub Issues で管理する（ユーザーが体験する不具合や機能要望、外部からの報告）
- **実装都合・CI・リファクタ等の内部タスク**: backlog.md で管理する（設計判断やハンドオフが必要な内部作業。詳細は下記 Backlog.md Workflow を参照）

判断に迷う場合は「ユーザーの視点で報告される事柄か」を基準にする。ユーザーが直接遭遇する問題や要望は GitHub Issues、開発側の都合で発生する作業は backlog.md とする。

## 自律的なタスク進行のための運用ルール

- **着手不可なタスク**: 外部要因（レビュー待ち、他タスクの完了待ち、仕様未確定など）で着手できない場合は、`backlog task edit --append-notes` で「何が解消すれば着手できるか」を明記する。理由が書かれていれば、次回セッションでその要因が解消したかどうかを自分で判断して再開できる。
- **次に着手すべきタスクが自明でない場合**: 優先順位は次の基準で判断する。
  1. ユーザー向けの不具合（GitHub Issues）が未対応なら最優先
  2. 着手可能な backlog タスクのうち、他の作業をブロックしているもの
  3. 着手可能な backlog タスクのうち、着手順（登録順・依存関係）が早いもの
  この基準で決められない場合のみユーザーに確認する。
- **タスク作成時のボード表示順**: backlog board の表示順は ordinal 順（priority 順ではない）。タスク作成後、既存タスクの ordinal を確認し、priority に応じた位置になるよう `backlog task edit --ordinal` で調整する。特に HIGH タスクが MEDIUM/LOW より上に来るようにする。

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
