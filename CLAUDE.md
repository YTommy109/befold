## Issue Tracking の使い分け

- **ユーザー向けのバグ・要望**: GitHub Issues で管理する（ユーザーが体験する不具合や機能要望、外部からの報告）
- **実装都合・CI・リファクタ等の内部タスク**: backlog.md で管理する（設計判断やハンドオフが必要な内部作業。詳細は下記 Backlog.md Workflow を参照）

判断に迷う場合は「ユーザーの視点で報告される事柄か」を基準にする。ユーザーが直接遭遇する問題や要望は GitHub Issues、開発側の都合で発生する作業は backlog.md とする。

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
