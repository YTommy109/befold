---
id: TASK-484.5
title: git 機能のスクリーンショットをカルーセルに追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 13:06'
updated_date: '2026-08-16 03:21'
labels: []
milestone: m-1
dependencies:
  - TASK-484.2
parent_task_id: TASK-484
priority: medium
type: task
ordinal: 710000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LP のスクリーンショットカルーセル（`site/src/views/landing.tsx:16-34`）は現在 6 枚で、Mermaid / SVG / Markdown / CSV / Source Code / Quick Open。**git 差分表示とサイドバーの git ステータスの画像が無い。**

TASK-484.2 で文章として紹介する機能を、画像でも見せられるようにする。

- git 差分表示（ソース表示、左右分割と上下のどちらを見せるかは判断する）
- サイドバーの git ステータスバッジ（変更ファイルが識別できている状態）

カルーセルの項目は `kind` を持ち、ファイル形式でなく機能を示すものにはキャプションのラベルが付く（Quick Open が前例）。alt テキストは日英ページで共通に使われるため英語で書かれている。既存 6 枚と画質・ウィンドウサイズ・テーマを揃えること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 git 差分表示のスクリーンショットがカルーセルにある
- [x] #2 サイドバーで変更ファイルが識別できている状態のスクリーンショットがカルーセルにある
- [x] #3 alt テキストとキャプションが既存項目の書き方に揃っている
- [x] #4 画像のサイズ・テーマ・ウィンドウ寸法が既存 6 枚と揃っている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 撮影素材を再現可能にする: scripts/make-git-demo-repo.sh を追加し、main + feature ブランチ・staged / unstaged / untracked / branchModified が揃った使い捨てリポジトリ（LRUCache のサンプルコード）を $TMPDIR 配下に生成する。既存 6 枚が sample/ を使うのに対し git 状態は sample/ では作れないため
2. scripts/capture-screenshots.applescript を拡張: targets に「表示モード（⌘3）」「サイドバーの表示対象をデモリポジトリにする」ための項目を足し、screenshot-7（LRUCache.swift を差分モード・左右分割・サイドバー無し）と screenshot-8（デモリポジトリをフォルダーで開きサイドバーのバッジが見える状態）を撮る。差分レイアウトは SourceDiffLayout を side-by-side に defaults write して確定させる
3. 撮影は既存と同条件（ダークモード / 原点 100,100 / 1280x800）。実行前後でシステム外観を元へ戻す
4. site/src/views/landing.tsx の SCREENSHOTS に 2 件追加（どちらも kind: 'feature'、alt は英語、caption は Git Diff / Git Status に相当する既存の書き方へ揃える）
5. 画像の寸法・ファイルサイズを既存 6 枚と突き合わせて確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
撮影の自動化と LP への配線までを実装。**画像 2 枚の実撮影が未完**（このセッションからは撮れない）。

- scripts/make-git-demo-repo.sh を追加。撮影素材の git リポジトリ（main + feature/eviction-policy、staged / unstaged / untracked / branchModified が同時に揃う）を $TMPDIR 配下へ毎回作り直す。befold 自身のリポジトリを汚さずに同じ状態を再現するため
- scripts/capture-screenshots.applescript を拡張。targets を 5 要素（5 番目が表示モードの ⌘1〜⌘3）にし、パスが '/' 始まりなら絶対パスとして扱う。screenshot-7 = LRUCache.swift を差分モード（⌘3、SourceDiffLayout を side-by-side に defaults write して固定）・サイドバー無し、screenshot-8 = Metrics.swift をソース表示（⌘2）・サイドバー有り（Sources/ 配下の 5 ファイルに 4 種のバッジが出る）
- site/src/views/landing.tsx の SCREENSHOTS へ screenshot-7 / 8 を kind: 'feature' で追加（caption は 'Git Diff' / 'Git Status'、alt は英語。Quick Open の前例に合わせ captionEn は付けない）

**ブロッカー（実測）**: このバックグラウンドセッションのプロセスに画面収録・アクセシビリティの TCC 許可が無い。`screencapture -x full.png` が 'could not create image from display'、System Events への osascript は AppleEvent タイムアウト（-1712）で失敗した。ディスプレイは 2560x1080 で撮影領域（100,100 起点の 1280x800）は収まっているので、幾何の問題ではない。

**再開手順**（ユーザーの対話セッションで実行）: システム設定でダークモードにし、ターミナルへ画面収録とアクセシビリティを許可してから `osascript scripts/capture-screenshots.applescript`（1〜8 を撮り直す）。撮影後に site/public/images/screenshot-7.png / 8.png の寸法が 1280x800 であることと、カルーセルの見た目を確認する。

撮影完了（ダークモード）。screenshot-7 = LRUCache.swift の左右分割差分（削除側/追加側が行番号付きで並ぶ）、screenshot-8 = Sources/ のサイドバーに 4 種のバッジ（branchModified の M ×2 / unstaged の M / staged の緑 M / untracked の ?）+ Metrics.swift のソース表示。

撮り直しの過程での修正 2 件。
- 1 回目・2 回目はシステム外観がライトのまま撮れており、既存 6 枚（ダーク）と揃わなかった。1〜6 が上書きされていたため git checkout で戻し、applescript に撮影番号の引数（例: `osascript scripts/capture-screenshots.applescript 7 8`）を足して、1 枚だけ足すときに既存画像へ無関係な差分が出ないようにした
- screenshot-8 の本文が 21 行で右側が空いていたため、make-git-demo-repo.sh の CacheMetrics に evictions / summary / recordEviction を足して 31 行にした（unstaged 側の差分は reset() のまま）

検証: 寸法は sips で 8 枚とも 1280x800。LP のレンダリング結果に screenshot-1〜8 が順に出ることと新しい alt 2 本が含まれることを使い捨ての vitest で確認（実行後に削除）。site の npx tsc --noEmit はクリーン、npm test は 181 件すべて成功。docs/dev/native-app-design.md の追随は不要（アプリの仕様ではなく配布サイトの掲載物の変更のため）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LP のカルーセルへ git 差分表示（screenshot-7: LRUCache.swift の左右分割差分）とサイドバーの git ステータス（screenshot-8: branchModified / unstaged / staged / untracked の 4 種のバッジ）を追加した。撮影素材は sample/ では作れないため scripts/make-git-demo-repo.sh を新設し、使い捨てのデモリポジトリで同じ状態を毎回再現する。capture-screenshots.applescript は表示モード（⌘1〜⌘3）と撮影番号の指定を受けられるようにした。検証: sips で 8 枚とも 1280x800、テーマは既存 6 枚と同じダーク（画像を目視）、LP のレンダリング結果に screenshot-1〜8 と新しい alt 2 本が出ることを使い捨ての vitest で確認、site の tsc はクリーンで npm test 181 件成功。
<!-- SECTION:FINAL_SUMMARY:END -->
