---
id: TASK-199
title: 検索(Find)がシンタックスハイライトの span 境界をまたぐピリオド入り文字列にヒットしない
status: Done
assignee:
  - '@claude'
created_date: '2026-07-30 10:08'
updated_date: '2026-07-30 10:57'
labels:
  - bug
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/336'
ordinal: 283000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
概要: デフォルト検索モード(大小文字区別なし/単語一致なし/正規表現なし)で `foo.bar` や `.bar` のようにピリオドの前後に文字列が付く語を検索すると 0/0 のままヒットしない。`.` 単体は検索できる。GitHub Issue #336 (https://github.com/YTommy109/befold/issues/336) で報告・原因調査済み。

原因: BefoldApp/BefoldKit/Resources/viewer-main.js の walk()/walkText()(696〜741行目)は #diagram-wrap 配下を再帰し、個々のテキストノード単位で正規表現マッチを行う。highlight.js のシンタックスハイライトやパス参照リンク化(_PATH_RE)がレンダリング時にトークン境界で <span> を挿入してテキストノードを分割するため、foo.bar のようなコード表記はコード内で foo / . / bar の3ノードに分かれ、ノードをまたぐマッチが検出できない。walk() のコメント(730〜731行目)に既知の制約として明記されている、実装時点で意図的に許容された制約。

buildFindRegExp(viewer.js:513-523) 自体のメタ文字エスケープには問題なし(Node で単体検証済み)。

対応方針(要件定義。実装時の詳細設計は着手時に再調査して記録する):
- walk/walkText を「テキストノード単位でマッチ」から「#diagram-wrap 配下(skipTags 除く)のテキストを一旦連結してオフセットを記録→連結文字列に対して既存 regex でマッチ→マッチ位置から (textNode, localOffset) を逆引きして Range を構築→<mark> 挿入」の方式に変更する
- 新しい状態や分岐を増やさず、既存の walk() 再帰構造をテキストノード収集フェーズに転用し、マッチ判定とDOM書き換えを分離するだけに留める(単純化検討済み: window.find() や CSS Custom Highlight API への置き換えも検討したが、既存の現在位置管理・scrollIntoView との整合を取るには結局同様のオフセット計算が必要になり差分が増えるため、Range ベースの最小差分方式を採用)
- 本チケットのスコープは検索(Find)機能のみ。_PATH_RE(パス参照リンク化)にも同じ制約があるが別機能のため対象外とし、必要なら別タスクとして切り出す(パス参照関連: TASK-122)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 コードブロックを含む .md/.mmd で、シンタックスハイライトにより `.` が別トークンとして分割される foo.bar のような文字列を、デフォルト検索モードで `foo.bar` / `.bar` / `foo.` として検索するとヒットしてハイライトされる
- [x] #2 大文字小文字区別・単語一致・正規表現の各トグルを有効にした状態でも、span 境界をまたぐマッチが検出できる
- [x] #3 単一テキストノード内で完結する既存の検索(従来の動作)に回帰がない
- [x] #4 BefoldApp/BefoldKit/Resources/__tests__/viewer-main.test.js に境界をまたぐマッチのテストケースが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. walk()/walkText() を「テキストノード単位でマッチ」から「テキストノード収集→連結文字列でマッチ→(node,offset)逆引き→Range構築→extractContents+insertNodeでmark挿入」の方式へ書き換える(既存のwalk再帰構造をcollectTextNodesとして転用、新規状態・分岐は増やさない)。
2. clearMarks() は mark を textContent で潰す実装だと mark 内の span 構造(境界をまたぐマッチの場合)を破壊するため、mark を子ノードで置き換える(unwrap)実装に変更する。
3. viewer-main.test.js に span 境界をまたぐ foo.bar / .bar / foo. のヒット、トグル有効時のヒット、クリア後のテキスト内容維持を検証するテストを追加する。
4. 既存テスト(単一テキストノードのケース)に回帰がないことを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
walk()/walkText() を Range ベースの実装(collectTextNodes → 連結文字列でマッチ → (node,offset) 逆引き → Range.extractContents + insertNode で <mark> 挿入)に書き換え。clearMarks() も mark を unwrap する方式に変更し、境界をまたぐマッチの span 構造を保持したままクリアできるようにした。検証: npx jest (BefoldApp/) で全 327 件(既存 81 件 + 新規 span 境界テスト 5 件を含む viewer-main.test.js 86 件)がパス。

追加修正: Range.extractContents() は境界をまたぐマッチの端で、部分的にしか含まれない祖先 <span> を空のまま DOM に残す仕様のため、検索バーへの1打鍵ごとに run() が呼ばれる結果、空 <span> が際限なく増殖し Markdown プレビューのレイアウトが崩れる回帰を確認(ユーザー報告)。walk() に pruneEmptyAncestors() を追加し、抽出直後に空になった祖先要素を除去するよう修正。連続打鍵を再現する回帰テストを追加し、npx jest で全327件パス(viewer-main.test.js は87件)を確認。

追加修正2(根本原因): collectTextNodes が #diagram-wrap 配下の全テキストノードを無条件に連結していたため、見出し・リスト項目・テーブル行/セル(行番号付きコードブロックの <tr>/<td>)などブロック要素の境界までまたいでマッチしてしまい、Range.extractContents() がテーブル構造を破壊してレイアウト全体が崩れていた(ユーザー報告のスクリーンショットで確認)。さらに locate() の境界解決が開始/終了で対称だったため、1つの span 内に収まる非交差マッチでも隣接 span を巻き込んで分割する副作用があった(「b e f o l d」のように分断される回帰)。walk() を bridgeTags(span/a/code/em/strong 等のインライン要素)でつながる範囲だけを1スコープとする collectScopes() に書き換え、見出し・段落・リスト項目・テーブル行/セル等はスコープの境界として扱うようにした。locate() も isStart 引数を追加し、開始側は次ノード優先・終了側は前ノード優先で境界を解決するよう修正(継ぎ目ちょうどのオフセットで無関係な隣接要素を巻き込まないため)。回帰テストを追加し、npx jest で全330件(viewer-main.test.js 89件)パスを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-main.js の Find 機能を、テキストノード単位のマッチからテキストノード連結+Rangeベースのマッチ・ハイライトへ変更し、シンタックスハイライト等の <span> 境界をまたぐ文字列(foo.bar 等)の検索ヒットに対応した。clearMarks() も mark unwrap 方式に変更し、境界をまたぐハイライト解除後も元の span 構造を保つ。viewer-main.test.js に境界をまたぐケース(デフォルトモード・トグル有効時・クリア後)のテストを追加し、npx jest で全327件パスを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
