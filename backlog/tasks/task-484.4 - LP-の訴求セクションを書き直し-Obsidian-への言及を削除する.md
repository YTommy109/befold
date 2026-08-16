---
id: TASK-484.4
title: LP の訴求セクションを書き直し Obsidian への言及を削除する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 13:06'
updated_date: '2026-08-16 01:39'
labels: []
milestone: m-1
dependencies:
  - TASK-484.3
parent_task_id: TASK-484
priority: high
type: feature
ordinal: 709000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
トップページ（`site/src/views/landing.tsx`）の訴求部分を、ふたつの読み手を同格に扱う構成へ書き直す。

**現状**（landing.tsx:128-174）は 2 つの philosophy セクションが並ぶ。

1. 「Claude が設計する。私は befold でレビューする。」— AI が生成した Markdown をレビューするというエンジニア向けの訴求。これは残す方向で扱う
2. 「vault に登録しなくていい。」— Obsidian を引き合いに出し、worktree を vault へ登録せずその場で読めることを訴求。**Obsidian への言及はこのセクションの日本語版（:155）と英語版（:166）の 2 箇所が全て**

Obsidian への言及は削除する。ただしこのセクションが担っていた「登録も設定もなく、その場のフォルダをすぐ読める」という訴求自体には価値があるため、**言及を消してセクションごと落とすのか、固有名詞なしで書き直すのかをこのタスクで決める**。

そのうえで、TASK-484.3 で整理した「Markdown を読む立場の人にとっての利点」を、エンジニア向けの訴求と同じ重みで並べる。どちらか一方が主で他方が従、という見え方にしないこと。

hero のコピー（「Markdown を行き来する。快適に。」/「数百のファイルを抱えたリポジトリのための、Mac 専用の軽量ビューア」）が、ふたつの読み手を同時に受け止められているかもあわせて見直す。「リポジトリ」という言葉が非エンジニアの入口として働くかは論点。

日英は 1 つの HTML に両方を埋め込み `lang` 属性で出し分ける構造のため、両方を同時に書き直すこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Obsidian への言及がサイトのソースから完全に無くなっている
- [x] #2 エンジニア向けの訴求と Markdown を読む立場の人向けの訴求が、同格に並んでいる
- [x] #3 hero のコピーがふたつの読み手のどちらも排除していない
- [x] #4 日本語と英語が同じ内容で書き直されている
- [x] #5 /features ページの導入文が LP の訴求と食い違っていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 現状の 2 つの philosophy セクションと hero、features 導入文、参照テストを確認する
2. Obsidian セクションの扱いを決める（削除か書き直しか）
3. TASK-484.3 の一覧から Markdown 読者向けの訴求を選び、日英を同時に書き直す
4. CSS の従属的な扱いを解消して 2 セクションを同格にする
5. typecheck / vitest と実レンダリング出力で検証し、完了処理・コミットする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
【Obsidian セクションの扱いの判断】固有名詞なしで書き直すのではなく、セクションが担っていた「登録も設定もなく、その場のフォルダをすぐ読める」という訴求をエンジニア向けセクションの 3 行目へ吸収し（befold . の code 表記も維持）、空いた枠を Markdown 読者向けの入口に置き換えた。philosophy セクションを 3 本に増やすと訴求が薄まるため、2 本のまま宛先を分ける構成にした。

【同格の担保】CSS の .philosophy.review（罫線なし・padding 縮小で 1 つ目を 2 つ目に従属させていた）を削除し、両セクションを同一の .philosophy に揃えた。宛先は新設の .philosophy-audience ラベル（コードを書く人へ / Markdown を読む人へ）だけで示す。

【訴求内容の裏付け】読者向けセクションの 3 行は TASK-484.3 の優先度 A/B から採用: Space プレビュー(A1)、GitHub と同じ見た目(A2)、mermaid 描画(A4)、0.2 秒更新(A3)、⌘F 検索(B1)、印刷/PDF(B4)。同タスクの制約に従い PDF は「印刷から PDF にも書き出せる」と印刷経由で表現し、専用エクスポートとは書いていない。未実装（レンダリング差分・比較基準の切替・目次）への言及なし。

【hero】「数百のファイルを抱えたリポジトリのための」が非エンジニアを排除するため「フォルダやリポジトリに置かれたまま読める」へ変更。テストが参照する Mac 専用 / Mac-only は維持。あわせて PAGE_DESCRIPTION（meta/OGP/構造化データが共有）もコーディングエージェント限定の記述から両読者を含む記述へ更新した。

【検証】site の vitest 181 件・typecheck ともに通過。一時テストで実レンダリング HTML をダンプし、philosophy セクションが 2 本・日英とも同内容・Obsidian/vault の残存 0 を確認（確認後に一時テストは削除）。features.tsx の導入文は機能とファイル形式の中立な説明で LP の訴求と矛盾しないため変更なし。

【レビュー後の文言確定（ユーザー指示）】初稿から次を変更した。(1) hero を「Markdown や Mermaid そしてソースコードも軽快に読める Mac 専用の軽量ビューア。」へ。(2) エンジニア向けセクションを 2 行に短縮し、befold . の行（旧 Obsidian セクションから吸収した「登録も設定もいらない」訴求）は削除。制作意図（大量のドキュメントのレビュー）と「編集機能を削り読むことに特化・Quick Look 対応」を置いた。(3) Quick Look の言及はエンジニア向けセクション側に置く（TASK-484.3 では非エンジニア層の入口 A1 と整理していたが、ユーザー判断でこの配置に確定）。(4) 読者向けセクションは Quick Look と ⌘F・印刷/PDF の言及を外し、難しい操作が不要であること（ファイルを開くだけ・覚えることも設定も不要）を中心に据え、更新の訴求は「LLM がファイルを更新すると 0.2 秒で反映」に変更。日英とも同内容。dev server のレンダリング出力で日英双方を確認し、typecheck と vitest 181 件の通過を再確認した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LP の訴求を、コードを書く人と Markdown を読む人のふたつの入口として同格に並べ直した。Obsidian への言及 2 箇所は削除し、そのセクションが担っていた「登録も設定もいらない」という訴求はエンジニア向けセクションへ吸収、空いた枠に Markdown 読者向けの訴求（Finder で Space、GitHub と同じ見た目と Mermaid の図、0.2 秒更新・⌘F・印刷から PDF）を TASK-484.3 の裏付け付き一覧から採用して置いた。CSS の .philosophy.review（1 つ目を 2 つ目に従属させる指定）を削除し、宛先ラベル .philosophy-audience だけで区別する対等な構成にした。hero の「数百のファイルを抱えたリポジトリのための」も非エンジニアを排除しない表現へ変更し、PAGE_DESCRIPTION も両読者を含む記述へ更新。検証は typecheck と vitest 181 件の通過に加え、一時テストで実レンダリング HTML をダンプして 2 セクションが同一マークアップ・日英同内容・Obsidian 残存 0 であることを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
