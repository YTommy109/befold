---
id: TASK-705
title: テストがホームディレクトリ直下に befold-test-* を作らないようにする
status: To Do
assignee: []
created_date: '2026-10-14 04:27'
updated_date: '2026-10-14 07:42'
labels:
  - test-infra
dependencies: []
priority: low
type: chore
ordinal: 894000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
一部のテストが実ユーザーのホーム直下(~/befold-test-<UUID>)に一時ディレクトリを作る。TempDir は deinit で削除するが、テストが止まって強制終了された実行などでは削除まで届かず残る(実測: 2026-10-14 時点で 79 個。作成日は 10/6〜10/7 で TASK-673 の調査時期と重なる。残った中身は a.md〜d.md / diagram.mmd+sub / symlink 用 real+link)。ホーム配下に作る理由は、サイドバーの上位フォルダー移動が「ホーム配下のみ許可」(DirectoryLister.isWithinHome)で、統合テストが本番既定の DirectoryLister.defaultHome を直接読むため。isWithinHome 自体は home: 引数を受け取れるので、判定規則のテストはシステムの一時ディレクトリで足りる。残るのは SidebarNavigator / ViewerWindowController を通す統合テストで、ここにホームを注入できる口が無い(未確認: 注入口を足せるか。rg 'defaultHome' で読み手を数えて確かめる)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 テストの実行でホームディレクトリ直下に befold-test-* が作られない(テスト実行前後で ls ~ の befold-test-* の数が変わらないことを実測する)
- [ ] #2 makeHomeTempDir() と TempDir(base: ホーム) の呼び出しが 0 件になり、makeHomeTempDir は削除されている
- [ ] #3 ホームの注入口を必須引数かシーム経由にし、本番既定は本番の組み立て箇所だけが指定する(テストが既定値を黙って使えない形にする)
- [ ] #4 注入口を使わずホーム配下へ作る書き方が再発したら落ちる仕掛けがある(テストまたは scripts の検査)
- [ ] #5 DirectoryListerTests など判定規則のテストはシステムの一時ディレクトリ + home: 注入で書かれている
<!-- AC:END -->
