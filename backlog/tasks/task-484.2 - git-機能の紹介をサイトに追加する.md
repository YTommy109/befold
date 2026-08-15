---
id: TASK-484.2
title: git 機能の紹介をサイトに追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 13:05'
updated_date: '2026-08-15 11:20'
labels: []
milestone: m-1
dependencies:
  - TASK-484.1
parent_task_id: TASK-484
priority: high
type: feature
ordinal: 707000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
v1.13.0 で stable になった git 連携をサイトの機能紹介に載せる。現在サイトには「git を知っているリンク解決」しか無く、差分表示とサイドバーの変更ファイル識別が紹介されていない。

**載せる（実装済み）**
- サイドバーの git ステータスバッジ — ファイル行に変更種別を 1 文字と色で表示、フォルダー行は配下の集約。staged / unstaged / untracked / branchModified を区別
- サイドバーの「変更ファイルのみ」表示
- ソース表示での差分表示 — ツールバーの 3 択（レンダリング / ソース / 差分）と `⌘1`〜`⌘3`、表示モードはファイル単位で永続化
- 差分レイアウトの上下・左右切替（`⌘\`、アプリ全体で共有）
- 「最近使ったリポジトリ」メニュー（worktree を階層表示）

**載せない（未実装）**
- レンダリング表示のままの差分表示（TASK-483）— 現在の差分はソース表示のみ
- 比較基準の切り替え UI（TASK-353）— 現在はデフォルトブランチとの merge-base に固定

文言は `site/src/views/shared.tsx` の `FEATURES` / `MORE_FEATURES` に足す（LP と /features が共に参照する単一情報源）。6 件ずつの現在の構成をどう組み替えるか（既存項目を `MORE_FEATURES` へ落として git を `FEATURES` へ上げるか等）はこのタスクで決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーで変更ファイルを識別できることが紹介されている
- [x] #2 ソース表示で git 差分を見られることが紹介されている
- [x] #3 差分がソース表示に限られること、比較基準が固定であることについて、実態と食い違う表現になっていない
- [x] #4 文言が shared.tsx の共有定数として定義され、LP と /features の両方に反映される
- [x] #5 日英の両方に同じ内容が入っている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 構成の決定: FEATURES へ git カードを 2 枚追加して 6→8 枚にする(既存カードの降格はしない)。根拠: (a) LP の .feature-grid は repeat(auto-fit, minmax(280px,1fr)) で枚数固定の前提が無く、8 枚は 4+4 / 3+3+2 に自然に折り返す(site/public/style.css:281)。(b) /features は [...FEATURES, ...MORE_FEATURES] を平坦な <dl> に連結するだけで枚数の影響なし(site/src/views/features.tsx:226)。(c) git 連携は v1.13.0 の目玉で、既存 6 枚を落とす理由が無い
2. FEATURES: 「ライブリロード」の直後に「Git 差分表示」「変更ファイルがわかるサイドバー」を挿入(ライブ反映→差分で読む→変更ファイルを辿る、の流れ)。差分カードは「ソースの差分」と明記し(実装はソース表示のみ: 差分モードは ViewerDisplayMode の第 3 モード)、比較基準には言及しない(デフォルトブランチとの merge-base 固定: BefoldApp/befold/App/GitComparisonBase.swift:24-36)。バッジカードは 1 文字+色・フォルダー集約・staged/unstaged/untracked/branchModified の区別(BefoldApp/befold/Viewer/GitStatusBadge.swift:4-13)と ⌃⌘G の絞り込みを載せる
3. MORE_FEATURES: 「git を知っているリンク解決」の直後に「最近使ったリポジトリ」を追加(タブ構成ごと再オープン: SessionRestorer.openRepository、worktree は本体配下に階層表示: RecentRepositoryEntry.mainRootPath)。既存「レンダリング / ソース切替」(⌘U)は実装に現存し矛盾しないため据え置き
4. 文言の制約: ドット付き文字列を書かない(file-types.test.ts:110 が拡張子と誤検出)。ショートカットは ⌘1 / ⌘2 / ⌘3・⌘\・⌃⌘G のみ使用(いずれも実装と SHORTCUTS 表に存在し shortcuts.test.ts:212-229 を通る)
5. 検証: (cd site && npm test && npm run typecheck)
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
採用した構成: FEATURES へ git カード 2 枚(「Git 差分表示」「変更ファイルがわかるサイドバー」)を「ライブリロード」直後に挿入して 6→8 枚、MORE_FEATURES へ「最近使ったリポジトリ」を「git を知っているリンク解決」直後に挿入して 6→7 件。既存項目の降格はしない(LP の .feature-grid は auto-fit で枚数固定の前提が無く、/features は両配列を平坦連結するため枚数の影響なし)。既存「レンダリング / ソース切替」(⌘U)は実装に現存し(MainMenuBuilder+ViewMenu.swift:20)矛盾しないため据え置き。

文言の裏付け: バッジは 1 文字+色・staged/unstaged/untracked/branchModified の 4 区別(GitStatusBadge.swift:10-13)、差分の比較基準はデフォルトブランチとの merge-base 固定(GitComparisonBase.swift:24-36)なので基準には言及せず「ブランチで加えた変更(コミット済み含む)」と表現、差分は「ソースの差分」と明記。最近使ったリポジトリはタブ構成ごと再オープン(SessionRestorer.openRepository)・worktree は本体配下に階層表示(RecentRepositoryEntry.mainRootPath)。

検証: (cd site && npm test) 181 件全通過 + typecheck クリーン。ガードの空振り確認として prose の ⌃⌘G を ⌃⌘Q に壊すと shortcuts.test.ts が 3 件落ちることを実測(「LP の記載が実装の割り当てに存在する」ほか)し、復元。AC は一時テスト(レンダリング済み HTML への日英文言の包含 + 「レンダリング差分」「比較基準切替」を示唆する表現の不在)を LP と /features の両方で実行して 2 件通過を確認後、削除。

native-app-design.md への反映は不要(紹介サイトの文言のみで、アプリの構成・型・永続化キーに変化なし)。prettier が shared.tsx を警告するが、site の CI は typecheck + vitest のみで prettier は設定も script も無く、既存コード全体が prettier 既定(ダブルクォート・セミコロン)と不一致のため対象外と判断。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
site/src/views/shared.tsx の共有定数へ git 連携の紹介を追加(FEATURES に差分表示・サイドバー変更識別の 2 カード、MORE_FEATURES に最近使ったリポジトリ)。差分はソースの差分と明記し比較基準には言及しない。vitest 181 件 + typecheck 通過、レンダリング済み HTML への日英反映を LP・/features 両方で一時テストにより実測検証。
<!-- SECTION:FINAL_SUMMARY:END -->
