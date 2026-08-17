---
id: TASK-507
title: サイドバーのコンテキストメニューからファイルの GitHub リンクを生成してコピーする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-17 02:10'
updated_date: '2026-08-17 04:09'
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
- [x] #1 サイドバーのコンテキストメニューにリモートのリンクをコピーする項目があり、相対パスをコピーの近くに置かれている
GitHub の origin を持つリポジトリ内のファイルで実行すると https://github.com/{owner}/{repo}/blob/{branch}/{相対パス} 形式の URL がクリップボードへ入る
SSH 形式（git@github.com:owner/repo.git）と HTTPS 形式（.git の有無を含む）のどちらの origin でも同じ URL が組み立てられることをユニットテストで確認している
パスに空白や日本語を含むファイルでも GitHub が解決できる形にエスケープされている
origin が無い / 対応外のホスト / git 管理外 / detached HEAD のいずれでも、項目が disabled で表示されクラッシュしない
未 push のブランチでもブランチ名のまま URL が生成される（判定を足していない）ことをテストで固定している
クリップボードへの書き込みが Pasteboard.writeString(_:) を経由しており、NSPasteboard を直接触っていない
リポジトリを開く処理が GitLibrary.withRepository(at:_:) を経由している
追加したメニュー項目の文言が Localizable.xcstrings に en / ja の両方で登録されており /l10n-check が通る
メニュー項目の文言が origin のホストに追随する（GitHub / GitLab / Bitbucket ではその名前が入り、解決できないときはホスト名を含まない中立の文言になる）
GitLab（/-/blob/）と Bitbucket（/src/）のホストごとの URL 形式がユニットテストで固定されている

- [x] #2 GitHub の origin を持つリポジトリ内のファイルで実行すると https://github.com/{owner}/{repo}/blob/{branch}/{相対パス} 形式の URL がクリップボードへ入る
- [x] #3 SSH 形式（git@github.com:owner/repo.git）と HTTPS 形式（.git の有無を含む）のどちらの origin でも同じ URL が組み立てられることをユニットテストで確認している
- [x] #4 パスに空白や日本語を含むファイルでもホスト側が解決できる形にエスケープされている
- [x] #5 origin が無い / 対応外のホスト / git 管理外 / detached HEAD のいずれでも、項目が disabled で表示されクラッシュしない
- [x] #6 未 push のブランチでもブランチ名のまま URL が生成される（判定を足していない）ことをテストで固定している
- [x] #7 クリップボードへの書き込みが Pasteboard.writeString(_:) を経由しており、NSPasteboard を直接触っていない
- [x] #8 リポジトリを開く処理が GitLibrary.withRepository(at:_:) を経由している
- [x] #9 追加したメニュー項目の文言が Localizable.xcstrings に en / ja の両方で登録されており /l10n-check が通る
- [x] #10 メニュー項目の文言が origin のホストに追随する（GitHub / GitLab / Bitbucket ではその名前が入り、解決できないときはホスト名を含まない中立の文言になる）
- [x] #11 GitLab（/-/blob/）と Bitbucket（/src/）のホストごとの URL 形式がユニットテストで固定されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitHubFileLink（純関数）を新設: origin URL 文字列 → owner/repo の正規化（SSH / ssh:// / https / .git 有無 / 末尾スラッシュ）と、slug + branch + 相対パス → https URL の組み立て（URLComponents でエスケープ）。github.com 以外は nil。
2. GitRepository に gitHubBlobURL(forFileAt:) を 1 本だけ足す。リポジトリを 1 回開き、workdir / origin remote / HEAD ブランチ / 相対パスをまとめて解決して URL? を返す。判定を分けず nil = 不可（disabled）に畳む。未 push 判定は行わない。
3. SidebarContextMenu に「GitHub リンクをコピー」を copyPath の隣へ追加し、URL? が nil のとき .disabled(true)。書き込みは Pasteboard.writeString。
4. Localizable.xcstrings に sidebar.context.copyGitHubLink を en/ja で追加（並べ替えない）。
5. テスト: GitHubFileLink の純関数テスト（SSH/HTTPS 同値・空白/日本語エスケープ・非 GitHub nil）、GitRepositoryIntegrationTests に origin あり/なし・detached HEAD・未 push ブランチのケース。
6. xcodegen generate → swift build / swift test → swiftlint ベースライン差分ゼロ → /l10n-check。

7. /review-design の結果（着手前レビュー）:
 - 項目1（判定の真実の源）: nil = disabled に畳む。理由（管理外 / unusable / origin 無し / 非 GitHub / detached）を区別して文言にしない。GitLibrary.OpenFailure が .unusable を 1 値へ畳んだ前例（BaseDirectoryIndicator の doc コメント）と同じ理由で、畳んだ値から理由を騙らない。キャッシュしないので .undetermined と .notARepository の区別は不要。
 - 項目2（既存の不変条件）: 相対パスは FileListModel.relativePathForCopy（baseDirectory 基準、git ルートとは限らない）を流用しない。GitHub リンクの相対パスは必ず git workdir 基準。PathRelativizer は共有してよいが基準ディレクトリは repo の workdir を渡す。
 - 項目3（消費経路）: 「相対パスをコピー」は SidebarContextMenu と ReferenceMenuPresenter の 2 経路にあるが、今回のスコープはサイドバーのみ（決定済み仕様に本文側の記載が無い）。本文側にも要るかは完了時に別タスク判断としてユーザーへ確認する。
 - 項目4（新しい状態の表示）: disabled のみ。ツールチップで理由を出さない（項目1 と同じ）。
 - 項目5（ライフサイクル）: 状態を持たず、キャッシュしない（ブランチは切り替わる）。該当なし。
 - 項目6（高頻度経路のコスト）★最大の論点: git 解決は View の body で行わない、が既存の規約（FileListModel.baseDirectory の doc）。SidebarContextMenu は FileListView の各行に .contextMenu で付いており、body が行ごとに評価されるならリポジトリオープンが行数分メインで走る（TASK-322 と同型）。設計は「init では何もせず、body 評価時に 1 回だけ解決する」に置き、**body の評価回数を計測して裏を取る**（NSLog カウンタを入れて実機で右クリックし、行数分でなく操作回数分であることを確認）。行数分だった場合は、SidebarNavigator がメイン外で解決して FileListModel に持たせる形へ切り替える（その場合は項目8 の世代管理が必要になる）。
 - 項目7（測るものと守るもの）: AC#6 は実 git で未 push のローカルブランチを作って URL に出ることを固定する（判定を足していないことの担保）。
 - 項目8（非同期の世代管理）: 同期解決 + 即コピーのため該当なし。項目6 の計測結果で非同期化するなら再検討する。
 - 項目9（粒度の担保）: NSPasteboard 直呼びを禁じる swiftlint カスタムルールは存在しない（.swiftlint.yml のカスタムルールは hardcoded_time_limit / git_repository_open_outside_git_library / unbounded_semaphore_wait の 3 つのみ、実測）。今回は Pasteboard.writeString を使うことで AC#7 を満たすに留め、ルール化は別タスク候補とする。
 - 項目10（行数・責務）: GitRepository グループ 249 行 / SidebarContextMenu 69 行（scripts/check-type-group-size.sh 実測）。追加は GitRepository へ約 50 行、SidebarContextMenu へ約 15 行で上限に余裕あり。stored property もプロトコル準拠も増えない（GitHubFileLink は純関数 enum として新設）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装・検証（2026-08-17）:
- 新規: BefoldApp/befold/App/GitHubFileLink.swift（純関数: リモート URL の正規化と blob URL 組み立て）、GitRepository+GitHubLink.swift（リポジトリを 1 回開いて workdir / origin / ブランチ / 相対パスを解決）。GitRepository.swift の workdirURL(of:) と branchName(of:) を private → internal に上げた（Swift の private はファイルスコープのため extension から見えない）。
- 相対パスに PathRelativizer.relativePath(of:relativeTo:) を使わなかった: 範囲外のファイルで絶対パスへフォールバックする実装のため、そのまま URL に埋まると嘘のリンクになる。ルート外は nil を返す専用ヘルパーにした。
- 高頻度経路の実測（設計レビュー項目6 の宿題）: SidebarContextMenu の body に NSLog カウンタを、FileListView の行構築に対照用カウンタを一時的に入れて計測。60 行の一覧を開いた直後で行構築 60 回に対しメニュー body の評価は 0 回。.contextMenu の内容は右クリック時にしか評価されないため、行数分の libgit2 オープンにはならない（TASK-322 の再来ではない）。計測用コードは撤去済み。
- 自動テスト: GitHubFileLinkTests（21 ケース）・GitRepositoryGitHubLinkTests（7 ケース）を追加。swift test 全体は 1597 tests / 253 suites すべて成功。
- swiftlint: 54 件（BefoldApp を CWD にした実測）。新規 3 ファイル・変更 2 ファイルいずれにも指摘なしでベースライン差分ゼロ。
- l10n: sidebar.context.copyGitHubLink を en/ja で追加。195 キー全件で翻訳漏れ・state 異常・プレースホルダ不一致なし。
- markdownlint-cli2 / check-doc-symbols.sh とも 0 件。docs/dev/native-app-design.md のコンポーネント表に GitHubFileLink と gitHubBlobURL を追記した。
- スコープ判断: 本文のパス参照メニュー（ReferenceMenuPresenter）には同項目を追加していない。決定済み仕様がサイドバーのみを指しているため。要否は別途ユーザー判断とする。
- 未確認: メニュー項目の実際の見え方（並び・disabled 表示）は GUI のため自動テスト対象外。実機での目視確認をユーザーに依頼中。

スコープ変更（2026-08-17、ユーザー判断）: メニュー文言を origin のホストに追随させ、URL 生成を GitLab / Bitbucket まで広げた。GitHubFileLink を RemoteForge へ一般化（ホスト判定・表示名・URL 形式を 1 型に集約）。GitLab はサブグループで owner/repo が 3 段以上になるため段数を落とさない。自建て（GitHub Enterprise / self-managed GitLab）はホスト名で判別できないため対象外。
- 文言の組み立ては format と中立文言を引数で受ける形にした。理由は実測: swift test では Localizable.xcstrings の解決が効かずキー名（"sidebar.context.copyForgeLink"）が返り、「Bitbucket が入る」というアサートが空振りで失敗した。内側で localized を引くとテストが差し込みロジックではなくバンドル解決を測ることになる。キーの登録は /l10n-check が担保する。
- 最終検証: swift test 1603 tests / 254 suites 成功。swiftlint 54 件（新規・変更ファイルに指摘なし＝ベースライン差分ゼロ）。l10n 196 キーで漏れ・state 異常・プレースホルダ不一致なし。markdownlint / check-doc-symbols.sh とも 0 件。
- GUI 実測（ユーザー確認）: GitHub origin のリポジトリで項目が有効表示になり、クリップボードへ https://github.com/YTommy109/befold/blob/sierra-lightning/CLAUDE.md が入った（pbpaste で確認）。git 管理外のファイルではグレーアウト表示。ホスト追随後の文言も期待どおり。ビルド済み .app 内の Localizable.strings に en/ja 両方の文言が入っていることも実測済み。
- 未 push のためリンクを開くと 404 になるのは決定済み仕様どおり（git ls-remote で sierra-lightning が未 push であることを確認）。push すればリンクは生きる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの右クリックメニューに「<ホスト> リンクをコピーする」を追加した。origin（SSH 形式 / HTTPS 形式）と HEAD のブランチ名、リポジトリルート基準の相対パスから GitHub / GitLab / Bitbucket それぞれの URL 形式でリンクを組み立て、メニュー文言もホスト名に追随する。作れない条件（git 管理外・origin なし・対応外ホスト・detached HEAD）はすべて nil へ畳んで項目を disabled で見せる。未 push 判定は足していない。検証: swift test 1603 件成功、swiftlint ベースライン差分ゼロ、l10n 196 キー問題なし、実機で有効表示・クリップボード内容・無効表示・文言を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
