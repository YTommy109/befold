---
id: TASK-483
title: レンダリング表示のまま差分を見せられるようにする
status: Done
assignee:
  - '@claude'
created_date: 2026-08-14 12:45
updated_date: '2026-11-21T00:40:00Z'
labels:
  - diff
milestone: m-4
dependencies: []
documentation:
  - docs/dev/native-app-design.md
priority: medium
type: feature
ordinal: 700000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
いま差分表示は「ソース相当の表示にだけ重なる」構造になっている。差分が描かれるのは `viewer-src/render.ts` の `renderShape` のうち shape が `code` / `csv-source` の分岐だけで、`markdown` / `csv-table` の分岐には差分の入る余地がない。`viewer-src/renderers.ts` の `_renderDiffHtmlIfAvailable` は `type === 'csv'` を明示的に弾いており、`BefoldKit/FileType.swift` の `supportsDiffDisplay` がその JS の挙動に合わせて `.csv` を false にしている。

つまり現状の制約は技術的な不可能性ではなく、差分を描く経路が 1 本しか通っていないことによる。CSV/TSV のテーブル表示と Markdown のレンダリング表示については、ソース行とレンダリング後の要素の対応付けが取れるため、レンダリングされた見た目のまま差分を重ねられる。

HTML / SVG / Mermaid / XML は対象外とし、差分はソース表示のままとする。ソース行とレンダリング結果を対応付ける手段（markdown-it の token.map に相当するもの）が無いため。

## 最初に決める論点：差分モードの意味（2026-11-20 追記）

起票後、差分は表示モードの 1 つになった。`ViewerDisplayMode` は `rendered` / `source` / `diff` の 3 択で、`diff` は「ソース表示に git 差分を重ねた状態」（`isSourceMode` が true）と定義されている（`befold/App/ViewerDisplayMode.swift`）。差分を描けない種別で `diff` を選ぶと、`ViewerDisplayMode.supported(for:)` がソース表示またはレンダリング表示へ降格する（`befold/App/ViewerDisplayMode+FileType.swift`）。

このため「レンダリング表示のまま差分」は、モードの意味を決めないと実装できない。

- CSV/TSV：現状 CSV のソース差分は存在しないので、`diff` を「テーブル＋差分」に読み替えても失うものはない。ただし `isSourceMode` を差分の有無と切り離す必要がある
- Markdown：`diff` は今ソース差分として動いている。レンダリング差分へ置き換えるとソース差分が失われ、AC #4（退行なし）と衝突する。4 つ目のモードを足すのか、差分モードの中にレンダリング／ソースの切替を持つのかを決める

CSV と Markdown の両方に効く判断なので、TASK-483.1 に着手する前に決める。メニュー（⌘1〜⌘3、`ViewerDisplayMode.menuItemTag`）と窓ごとのモード記憶（`WindowPresentationMemory`）への影響もあわせて確認する（未調査）。

## 設計の前提になる事実

- 差分は前後 1,000,000 行の文脈付きで取得している（`GitDiffReader.wholeFileContextLines`）。差分本文に旧版・新版の全文が含まれるため、旧版のレンダリングや削除ブロックの前後文脈付きの描画に追加の git 読み込みは要らない
- 比較の起点は HEAD 固定ではなく選べる（`GitComparisonBase`）
- 差分ジャンプ（次の変更へ）は DOM のクラスではなく `data-diff-block` を数える（`viewer-src/jump-providers.ts`）。レンダリング差分でもこの属性を付けないとジャンプが効かない
- 単語単位の差分は `viewer-src/diff-words.ts`（`wordDiffRanges` / `markWordRanges`）にある
- 差分表示中のチャンク追記は `render.ts` の `appendChunk` が `_mmdDocument.shape() === 'diff'` で DOM へ反映しない

サブタスクは CSV/TSV → Markdown の順に進める。CSV/TSV は表という表現がもともと行単位で差分の概念と噛み合い、削除行を赤い行として自然に挿入できるため設計判断が少ない。Markdown は「レンダリング結果に存在しない削除ブロックをどう見せるか」の設計が先に要る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CSV/TSV をテーブル表示したまま、追加・削除されたレコードが色分けして表示される
- [x] #2 Markdown をレンダリング表示したまま、変更のあったブロックが色分けして表示される
- [x] #3 HTML / SVG / Mermaid / XML の差分表示はソース表示のままで、挙動が変わらない
- [x] #4 既存のソース表示での差分（inline / side-by-side）の見た目と操作が退行していない
- [x] #5 差分モードの意味（種別ごとの読み替えか、新しいモードか）が TASK-483.1 の着手前に決まり、選ばなかった案とその理由が記録されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 差分モードの意味の決定（2026-11-21、AC #5）

**採用: ViewerDisplayMode に 4 つ目の case `renderedDiff`（レンダリング差分、⌘4）を足す。** isSourceMode = .source/.diff、showsDiff = .diff/.renderedDiff で、どちらもモード値だけの純粋関数のまま保つ。種別ごとの成否は従来どおり `supported(for:)` 1 箇所で降格する: renderedDiff は CSV/TSV・Markdown だけで成立し、それ以外では .diff（不可なら source/rendered）へ。.diff は CSV/TSV では成立しない（CSV のソース差分は存在しない）ので renderedDiff へ降格する。レンダラ境界は既存の 2 入力（isSourceMode=false + DiffState）のままで、JS は「レンダリング表示 + 差分あり」をレンダリング差分として描く。この組み合わせは今は JS に届かない（差分の取得と送信は showsDiff のときだけ: ViewerDiffPresenter.refresh / DocumentSurfaceStack.diffState。QuickLook は差分を送らない: OneShotRenderer）ため、HTML/SVG/Mermaid/XML の挙動は変わらない（AC #3）。⌘4 は TASK-356 の時点で表示モード用に予約済み（MainMenuBuilder+ViewMenu の addSidebarTreeLayoutItem のコメント）。窓ごとの記憶（WindowPresentationMemory）はメモリ上の PathKeyedTable で rawValue 永続化が無く、復元は supported(for:) を通るので追加の移行は要らない。

**採らなかった案と理由**
- 種別ごとの読み替え（CSV/Markdown では .diff = レンダリング差分）: isSourceMode がモードだけで決まらなくなる（種別に依存する）。Markdown のソース差分が失われ AC #4 と衝突する
- 差分モードの中にレンダリング／ソースの切替を別の保存値で持つ: ViewerDisplayMode の doc コメントが退けた『2 値で持つと不整合な組み合わせが状態として作れる』形に戻る
- 差分レイアウト（inline / side-by-side）に 3 つ目の値『rendered』を足す: レイアウトはアプリ全体の設定で、コード種別では意味を持たない値になる。isSourceMode が設定値にも依存する

**レンダリング差分の共通方針（CSV / Markdown）**: 差分本文（-U1000000 で全文入り）から新旧の全文を復元し、ソース行をまとめた単位（CSV はレコード、Markdown はトップレベルのブロック）ごとに『変更あり』を判定して、削除単位は削除色で、追加単位は追加色で文書順に挿入する。レイアウトの切替（inline / side-by-side）はレンダリング差分では効かず常に 1 カラム（canToggleDiffLayout を false にする）。

実アプリでの確認（2026-11-21、xcodebuild Debug を .build/xcode に出して起動。git 管理下のデモリポジトリで CSV・Markdown・HTML を変更して確認）
- CSV ⌘4: テーブルのまま削除行（-、赤）と追加行（+、緑）が出る。引用符内改行のレコードも正しい行に色が付く。ツールバーは 4 つ目のセグメントが選択状態（AC #1）
- Markdown ⌘4: 段落の差し替え、リストへの項目追加（旧リスト赤・新リスト緑）、mermaid 図の変更（旧図・新図とも描画）が色分けされる（AC #2）
- Markdown ⌘3: 従来どおり左右分割のソース差分（語単位の強調つき）（AC #4）
- HTML ⌘4: 4 つ目のセグメントは無効で、押してもレンダリング表示のまま。⌘3 は従来どおりソース差分（AC #3）
- 起動時に macOS の『書類フォルダへのアクセス』許可ダイアログが出たが、ユーザーの判断事項なので触っていない

実アプリ追加確認: Markdown の ⌘3 で ⌘\ を押すと左右分割 ↔ 上下（インライン）が切り替わる（AC #4）。⌘4 中に ⌘\ を押しても何も変わらず、⌘3 に戻ったときのレイアウトも変わっていない（canToggleDiffLayout が false）。確認後にレイアウトを元の左右分割へ戻した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
差分表示に 4 つ目の表示モード『レンダリング差分』（⌘4）を足し、CSV/TSV はテーブル表示のままレコード単位で、Markdown はレンダリング表示のままトップレベルブロック単位で追加・削除を色分けできるようにした（TASK-483.1〜.4）。モードの意味の決定と退けた案は Notes に記録。HTML/SVG/Mermaid/XML は supportsRenderedDiff が false でソース差分のまま、既存のソース差分（inline/side-by-side）は変更なし（jest・swift test・webview-smoke 通過）。未実施: 実アプリでの目視確認、サイトのショートカット表記（⌘1/⌘2/⌘3）の更新。
<!-- SECTION:FINAL_SUMMARY:END -->
