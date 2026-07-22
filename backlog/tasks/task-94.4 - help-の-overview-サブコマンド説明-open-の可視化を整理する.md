---
id: TASK-94.4
title: help の overview/サブコマンド説明/open の可視化を整理する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-22 02:22'
updated_date: '2026-07-22 13:12'
labels: []
dependencies:
  - TASK-94.1
  - TASK-94.3
parent_task_id: TASK-94
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/befold/App/BefoldRootCommand.swift の CommandConfiguration(30-50行)を以下の観点で整理する:
1. overview(abstract)が長い。「OVERVIEW: Mermaid/Markdown ビューア。」の後は USAGE のみで十分なので、discussion の内容を整理・簡潔化する。
2. bookmark/check の CommandConfiguration に abstract がなく、--help のサブコマンド一覧に説明が出ない。何をするサブコマンドか一目で分かる abstract を追加する。
3. open が実は defaultSubcommand であり、パス指定なしの起動時の既定挙動であることが --help から分からない(OpenPathsCommand は shouldDisplay: false で非表示)。open がデフォルト挙動であることを discussion 等で明示する。
4. open のオプション(--hidden-files 等)がサブコマンド(open)側にぶら下がっており、`befold open --help` を実行しないと見えない。これらはパス省略時の既定動作のオプションなので、トップレベルの --help からも分かるようにする(swift-argument-parser での実現方法を調査し、実装方針を決定する)。

TASK-94.1(--version)・TASK-94.3(言語方針)の結果を踏まえて最終的な文言・構成を決定すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold --help の OVERVIEW が簡潔になり、詳細説明は USAGE 以降に整理されている
- [x] #2 befold --help のサブコマンド一覧で bookmark/check それぞれが何をするか一目で分かる説明が表示される
- [x] #3 befold --help から、パス省略時(オプションのみ指定時含む)の既定動作が open サブコマンドであることが分かる
- [x] #4 befold --help から open 相当のオプション(--hidden-files 等)の存在が分かる、または befold <path> --help 相当で確認できることが明記されている
- [x] #5 BefoldRootCommandTests 等の既存 CLI テストが引き続き成功し、変更箇所のテストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. (単純化検討) item4「openのオプションをトップレベルhelpからも分かるようにする」について、rootコマンドにopenの@OptionGroupを合成する案も検討したが、root自身は意図的にpositional引数を持たない設計(TASK-73.9/73.10のサブコマンド名衝突回避のため)であり、これを崩すと同種のバグを再導入するリスクが高い。よって最小変更で対応する: OpenPathsCommand を shouldDisplay: true にしてSUBCOMMANDS一覧に'open'として表示し、ユーザーが自然に `befold open --help` に辿り着けるようにする(既存のdefaultSubcommand機構は変更しない)。
2. root の discussion を大幅に短縮する(item1)。「--」エスケープの説明とsymlink再インストールの案内は、開く操作に固有の詳細なので open サブコマンドの discussion 側へ移す。
3. BookmarkPassthroughCommand/CheckPassthroughCommand に一目でわかる abstract を追加する(item2)。
4. OpenPathsCommand の abstract/discussion を更新し、デフォルト挙動であることと利用可能なオプションの参照先を明記する(item3, item4)。
5. TDD: 各CommandConfigurationのabstract/discussion/shouldDisplayの期待値をテストで先に書き、RED確認後に実装する。
6. swift test 全体・swift run befold --help / open --help の実機確認で回帰がないことを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。swift run befold --help で確認: SUBCOMMANDSに open(default)/bookmark/check がそれぞれ一目でわかる説明付きで表示される。OVERVIEWは簡潔になり、詳細(--エスケープ・symlink再インストール)はopenサブコマンドのdiscussionへ移した。swift test --skip Integration --skip FileWatcherTests で全563件成功。

フォローアップ: openのdiscussionからsymlink再インストール案内を削除した。理由(ユーザー指摘): このメッセージが必要なユーザー(symlinkが壊れている古いバージョン利用者)にはそもそも表示されず、表示されるユーザーには不要なため。swift test 563件成功を再確認。

フォローアップ: --hidden-files/--sort/--line-numbers のhelp文言に対象機能(サイドバー/ソース表示)を明記した(ユーザー指摘: 何の機能かわかりにくい)。

フォローアップ: openのオプション(--hidden-files/--sort/--line-numbers/--source/--preview)をOpenCLIOptions構造体に切り出し、rootとOpenPathsCommandの双方で@OptionGroupとして共有することで、トップレベルの--helpのOPTIONSにも表示されるようにした(swift-argument-parserは親子で同一OptionGroup型を宣言すると親でdecode済みの値を子が引き継ぐため、二重パースや値の消失は起きない)。実機のサブプロセステストで--helpのOPTIONS表示とサブコマンド省略時のパース挙動の両方を回帰確認。swift test 565件成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldRootCommand.swift の CommandConfiguration を整理した: (1)OVERVIEWをMermaid/Markdown viewer.のみに近い簡潔さにし、詳細説明はopenサブコマンドのdiscussionへ移動、(2)bookmark/checkにそれぞれ一目でわかるabstractを追加(Manage bookmarks. / Check whether befold can open a file/folder.)、(3)OpenPathsCommandをshouldDisplay:trueにしてSUBCOMMANDS一覧に表示させ、ArgumentParserが自動的に'open (default)'と表示することでデフォルト挙動であることが分かるようにした、(4)openのオプションはOpenCLIOptions構造体に切り出し、rootとOpenPathsCommandの双方で@OptionGroupとして共有することで、トップレベルの--helpのOPTIONSにも表示されるようにした。TDDで各CommandConfigurationのabstract/discussion/shouldDisplayをテストで先に固定してから実装。swift test(565件)全て成功、swift runでの実機出力も確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
