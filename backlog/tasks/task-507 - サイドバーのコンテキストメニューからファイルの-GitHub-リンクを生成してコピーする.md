---
id: TASK-507
title: サイドバーのコンテキストメニューからファイルの GitHub リンクを生成してコピーする
status: To Do
assignee: []
created_date: '2026-08-17 02:10'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 738000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーで右クリックしたファイルについて、GitHub 上の該当ファイルを指す URL を組み立ててクリップボードへ入れられるようにする。既存の「相対パスをコピー」の隣に置く。

用途は、開いている資料を他人や AI に「これを見て」と渡すこと。コピーではなく生成（ローカルのパスと git の情報から URL を組み立てる）。

決定済みの仕様（2026-08-17 にユーザーと確認）:
- URL 形式はブランチ名を使う: https://github.com/{owner}/{repo}/blob/{branch}/{repo からの相対パス}
  permalink（コミット SHA 固定）は採らない。理由は、用途が「最新版を共有する」であり、行番号付き引用のような permalink が効く場面が befold にまだ無いため。
- 現在ブランチがリモートに無い（未 push / ローカル専用）場合も、判定を足さずそのままブランチ名で生成する。push すればリンクは生きるため、一時的に 404 になるだけ。
- origin が無い / GitHub 以外のリモート / git 管理外のファイル / detached HEAD の場合は、メニュー項目を隠さず disabled で表示する（機能の存在に気づけるようにするため）。

実装の前提（調査済み、いずれもコード参照）:
- コンテキストメニューは BefoldApp/befold/Viewer/SidebarContextMenu.swift。既存の「相対パスをコピー」は 25 行目、キーは sidebar.context.copyPath。
- クリップボード書き込みは BefoldApp/befold/App/Pasteboard.swift の writeString(_:) に集約する方針。直接 NSPasteboard を触らない。
- git は外部プロセスではなく libgit2 経由（ADR 0006）。リポジトリを開く唯一の入口は GitLibrary.withRepository(at:_:) で、git_repository_open の直呼びは swiftlint カスタムルールで禁止されている。
- 作業ツリールートは GitRepository.root(forFileAt:)（76 行目）、ブランチ名は GitRepository.branchName(of:)（200 行目、detached/bare は nil）が既にある。
- 不足しているのは remote URL の取得だけ。git_remote_* の利用は現状ゼロなので、origin の URL 取得と SSH 形式（git@github.com:owner/repo.git）/ HTTPS 形式の正規化を新規に書く必要がある。
- ローカライズは befold/Resources/Localizable.xcstrings に en / ja を追加し、String(localized:bundle:.l10n) で引く。キーの追加時に既存の並びをソートし直さない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーのコンテキストメニューに GitHub リンクをコピーする項目があり、相対パスをコピーの近くに置かれている
- [ ] #2 GitHub の origin を持つリポジトリ内のファイルで実行すると https://github.com/{owner}/{repo}/blob/{branch}/{相対パス} 形式の URL がクリップボードへ入る
- [ ] #3 SSH 形式（git@github.com:owner/repo.git）と HTTPS 形式（.git の有無を含む）のどちらの origin でも同じ URL が組み立てられることをユニットテストで確認している
- [ ] #4 パスに空白や日本語を含むファイルでも GitHub が解決できる形にエスケープされている
- [ ] #5 origin が無い / GitHub 以外のリモート / git 管理外 / detached HEAD のいずれでも、項目が disabled で表示されクラッシュしない
- [ ] #6 未 push のブランチでもブランチ名のまま URL が生成される（判定を足していない）ことをテストで固定している
- [ ] #7 クリップボードへの書き込みが Pasteboard.writeString(_:) を経由しており、NSPasteboard を直接触っていない
- [ ] #8 リポジトリを開く処理が GitLibrary.withRepository(at:_:) を経由している
- [ ] #9 追加したメニュー項目の文言が Localizable.xcstrings に en / ja の両方で登録されており /l10n-check が通る
<!-- AC:END -->
