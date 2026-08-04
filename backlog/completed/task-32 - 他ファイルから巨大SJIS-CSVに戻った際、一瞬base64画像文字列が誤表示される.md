---
id: TASK-32
title: 他ファイルから巨大SJIS CSVに戻った際、一瞬base64画像文字列が誤表示される
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-16 13:44'
updated_date: '2026-07-16 14:23'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 30
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーで別ファイルを表示した後、巨大SJIS CSVタブ(またはファイル)に戻ると、一瞬 'iVBORw0KGgo...' のようなbase64エンコード画像(PNG)らしき文字列がそのままテキストとして表示され、その後しばらくして正しいCSV内容に置き換わる現象が観測された。CSVファイルにこの内容が含まれるはずはなく、直前に見ていた別ファイル(画像)のレンダリング結果、またはキャッシュされたコンテンツが誤って一瞬適用されている可能性がある。ViewerStore の loadGeneration による世代管理、ViewerWebView.Coordinator の lastRenderedContentRevision 判定、NormalizedTextCache/textCache の再利用ロジックに、ファイル切替時の競合や取り違えがないか調査する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 base64文字列が一瞬表示される再現条件が特定されている(どのファイル間の切替で発生するか、タイミング条件を含む)
- [x] #2 誤表示の原因(世代管理・レンダリングキャッシュ・コンテンツ取り違えのいずれか)が特定されている
- [x] #3 原因箇所に対する修正方針、または追加調査が必要な場合はその範囲が明確になっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerStore/ViewerWebView/NormalizedTextCache/ContentLoader を読み、非同期読込パイプラインでの状態不整合を調査する
2. 発見した原因を task の notes に記録する
3. 各 AC に調査結果の根拠を紐付けて finalization へ進める
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 再現条件(AC#1)
サイドバーで画像ファイル(PNG等)を表示 → 巨大な行指向ファイル(SJIS CSV等)に切り替える。
画像→巨大CSVの遷移で、巨大CSVの非同期読込(NormalizedTextCache 生成のフルSJISデコード+行インデックス構築)が完了するまでの間、一瞬だけ画像のbase64文字列がCSVとして誤表示される。

## 原因(AC#2): fileType と content の更新タイミングのずれによる不整合(生成/世代管理やキャッシュキー衝突ではない)
ViewerStore.openFile() (ViewerStore.swift:128-141) が
  filePath = url
  fileType = FileType(url: url)   // 同期・即時
  loadContent()                    // 非同期。content/contentRevision は apply() 完了まで不変
という順で filePath/fileType のみを即時更新し、content は loadContent() 内の
バックグラウンド computeLoad → apply()(ViewerStore.swift:295-331)が完了するまで
「前ファイルの content」のまま据え置かれる。

ViewerContentView.body は store.content と store.fileType を個別の @Observable プロパティ
として読み、両方を ViewerWebView.updateContent(...) に渡す(ViewerContentView.swift:34-36)。

ViewerWebView.Coordinator.updateContent の再描画判定(ViewerWebView.swift:396-401)は
  needsRender = contentRevision != lastRenderedContentRevision || fileType != lastRenderedFileType || ...
であり、fileType の変化だけでも再描画をトリガーする。そのため、
「fileType は新CSV / content はまだ前の画像のbase64文字列」という組み合わせで
SwiftUI が中間状態を描画してしまい、CSVとして base64 文字列が一瞬表示される。
巨大SJIS CSVでは NormalizedTextCache の初期化(SHA-256計算+全文SJISデコード+行インデックス構築)が
重いため、この不整合ウィンドウが体感できるほど長くなる。

contentRevision 自体は正しく機能しており(単にまだインクリメントされていないだけ)、
NormalizedTextCache/textCache のキー衝突でもない。fileType と content が
「常に同じファイルを指す」という前提を Coordinator 側が持っているのに対し、
ViewerStore 側でその2つを独立したタイミングで更新していることが原因。

## 修正方針(AC#3)
新しいフラグや世代カウンタを追加する必要はない(単純化を優先)。
openFile() で filePath/fileType を即時に書き換えるのをやめ、
既に「表示状態への一括適用」の唯一の場所として存在する apply()(ViewerStore.swift:293-294 のコメント参照)
の中で filePath/fileType を content/contentRevision と同時に更新するよう変更する。
loadContent() は既に fileType をローカル変数としてキャプチャして
バックグラウンド計算に渡しているため(ViewerStore.swift:193, 204)、
下流の処理は fileType が openFile() 時点で即時更新されていることに依存していない。
これにより filePath/fileType/content/contentRevision が常に単一のアトミックな単位として
更新されるようになり、Coordinator 側の前提と一致する。同種の不整合は
画像→CSV以外のファイル種別切替全般でも起こりうるため、この修正で同時に解消する。

調査は general-purpose agent による調査結果をコード直読で検証済み
(ViewerStore.swift:128-141, 293-331、ViewerWebView.swift:332-401、
ViewerContentView.swift:34-36 を実際に確認)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore.openFile() が filePath/fileType を同期即時更新する一方、content/contentRevision は
loadContent() の非同期処理(computeLoad→apply())完了まで前ファイルのまま据え置かれることを、
ViewerStore.swift / ViewerWebView.swift / ViewerContentView.swift のコード直読で確認した。
ViewerWebView.Coordinator の再描画判定が fileType の変化だけでもトリガーされるため、
「新fileType + 前ファイルのcontent」という中間状態が一瞬描画される。
画像→巨大SJIS CSVの遷移だと NormalizedTextCache の初期化(SHA-256+全文SJISデコード+行インデックス構築)が
重く、この不整合ウィンドウが体感できる長さになる。
世代管理(loadGeneration/contentRevision)自体は正しく機能しており、キャッシュキー衝突でもない。

修正方針: filePath/fileType の更新を openFile() の即時代入からやめ、既存の一括適用箇所である
apply()(ViewerStore.swift:293-331)内で content/contentRevision と同時に更新するよう変更する。
新たな状態やフラグは不要(単純化優先)。本タスクは調査のみで、実装は別途対応する。
<!-- SECTION:FINAL_SUMMARY:END -->
