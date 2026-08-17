---
id: TASK-485.2
title: Markdown レンダリング表示で h2 / h3 見出しを前後移動できるようにする
status: Done
assignee: []
created_date: '2026-08-14 13:18'
updated_date: '2026-08-17 11:53'
labels: []
milestone: m-6
dependencies:
  - TASK-485.1
parent_task_id: TASK-485
priority: medium
type: feature
ordinal: 713000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-485.1 で共通基盤と `HeadingJumpProvider`（`h2, h3` 固定）まで入った。本タスクはこれを
**差し替えず拡張**して、実用に足る見出しジャンプにする。

## このタスクでやること（ユーザー要望 2026-08-17）

1. **h1 も対象に含める。** h1 が複数ある Markdown があるため、485.1 の「h1 は文書題名 1 つ」という
   前提は成り立たない。
2. **h1 / h2 / h3 をユーザーが選べるトグルを付ける。** 検索バーの 3 トグル（Aa / ab| / .*）と同じ形で
   ジャンプバーに並べる。
3. **目印の候補を視覚的に示す。** 次にどこへ飛ぶか予想できるようにする。
   **見せ方はバーを開いている間だけ下線**（閉じれば普段の表示に戻る。検索バーがヒットを
   黄色で示すのと同じ「開いている間だけ」の考え方）。

## トグル状態の持ち方（ユーザー指定）

**既定値は 3 つとも ON。ライブ値はウィンドウ単位で保持し、ウィンドウを閉じたり
アプリを再起動したときは最後にユーザーが操作した状態を復元する。**
これは `SidebarDisplayDefaults`（サイドバーの不可視ファイル表示ほか 4 値）と同じ形で、
ADR 0002「窓の状態」に沿う。

- ライブ値: 窓ごと（viewer 側の JS が持つ。窓ごとに WebView があるので自然に窓ごとになる）
- 保存値: 「**次に開くウィンドウの出発点**」。窓が値を変えるたび後勝ちで記録する
- 参考実装: `befold/App/SidebarDisplayDefaults.swift`（読み取りを持たない
  `SidebarDisplayDefaultsRecording` プロトコルで書き戻す）

**注意**: 検索の 3 トグル `FindOptionsPreference`（`BefoldKit/FindOptionsPreference.swift`）は
doc コメント上「アプリ全体の単一状態」と位置づけられた別系統。配線経路
（postMessage → `BridgeMessageRouter` → preference → `initialFindOptionsScript` で注入）は
そのまま参考になるが、**意味論は `SidebarDisplayDefaults` に揃えること**。

## 設計上の論点（`/review-design` で扱う）

- **プロバイダへ設定を渡す経路。** 485.1 の `JumpProvider.collect(root)` は引数を取らない。
  レベル選択をどう届けるか（collect の引数を増やす / プロバイダが可変状態を持つ /
  コントローラがオプションを持つ）。485.1 で決めた形をどこまで変えるか
- **トグル UI をどこが持つか。** 差分の変更ブロック（485.3）や関数定義（485.4）にはレベルの概念が無い。
  ジャンプの種類ごとに違うトグルを出す形にするのか、当面は見出し専用の決め打ちにするのか
- **候補の下線が既存の見出し装飾と干渉しないか。** github-markdown-css は h1 / h2 に
  `border-bottom` を持つ。下線をどう表現すれば見分けられるかは実測（スナップショット）で決める
- 3 つとも OFF にしたときの表示（0/0 でよいか、最低 1 つを ON に強制するか）
- 485.1 のテストは「h1 は目印にしない」を固定している。この変更で書き換える対象になる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Markdown レンダリング表示で h2 / h3 を文書順に前後移動できる
- [x] #2 現在位置と総数が検索窓と同じ形で表示される
- [x] #3 見出しが 0 個の文書で操作しても壊れず、その旨が分かる
- [x] #4 見出し列挙の純粋な部分（要素列 → 目印列）に JS のユニットテストがある
- [x] #5 TASK-485.1 で入れた HeadingJumpProvider を差し替えず拡張する（別実装を立てない）
- [x] #6 h1 / h2 / h3 のうち ON にしたレベルの見出しだけが目印になる
- [x] #7 トグルの既定値は 3 つとも ON で、ライブ値はウィンドウごとに独立している（1 つの窓の操作が他の窓へ伝播しない）
- [x] #8 最後に操作した状態が次に開くウィンドウとアプリ再起動後に復元される
- [ ] #9 ジャンプバーを開いている間だけ、目印になる見出しが下線で示され、閉じると元の表示に戻る
- [ ] #10 候補の下線が h1 / h2 の既存の border-bottom と見分けられることをスナップショットで確認している
- [ ] #11 TASK-485.1 の HeadingJumpProvider を差し替えず拡張する（別実装を立てない）
- [ ] #12 3 つとも OFF にしても壊れず、その状態がユーザーに分かる
- [ ] #13 見出し列挙の純粋な部分（要素列 → 目印列）に JS のユニットテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
`/review-design` を 1 回実施（項目 1〜7 と 8〜10 を別レビュアーで並列）。実装方針を変える指摘が
9 件出たので、それを反映して確定した設計。

## 確定した決めごと

### F1. 保存は Bool 3 本ではなく単一キー（未設定と「全 OFF」を区別する）
`UserDefaults.bool(forKey:)` は未設定時 false を返すため、Bool 3 本だと
**「初回（未設定）」と「ユーザーが 3 つとも OFF にした」が同じ (false,false,false)** になる。
既定 3 つとも ON を実装すると、ユーザーが全 OFF にした状態が次の窓・再起動で勝手に ON へ戻る。

単一キー `"HeadingJumpLevels"` に `stringArray` で `["h1","h2","h3"]` を保存する。
**空配列 = 全 OFF、キー欠如（nil）= 未設定 → 既定 3 つとも ON。**
前例: `SidebarStateStore.swift:37`（`object(forKey:) != nil` で未設定を見る）、
`PathListDefaults.swift:38`、`CodeFontPreference.swift:41`。
`UserDefaults.register(defaults:)` はリポジトリ内 0 件なので新規に持ち込まない。
単一キーは `SidebarDisplayDefaults.record` が 4 値をまとめて書くのと同じく、
部分書き込みによる中間状態も構造的に起きない。

### F2. 窓へ渡すのは「読み取りを持たない記録用プロトコル」だけ
ユーザー指定の粒度（ライブ値は窓ごと・保存値は次に開く窓の出発点）を**構造で**守る。

- `SidebarDisplayDefaultsRecording`（`befold/App/SidebarDisplaySettings.swift:65`）と同じ形で
  `HeadingJumpLevelRecording`（`record(_:)` のみ）を定義する
- **プロトコルは BefoldKit に置く。** 受け口の `BridgeMessageRouter` は BefoldRenderKit にあり、
  `befold` アプリターゲットを import できない（検索側が成立しているのは
  `FindOptionsPreference` が BefoldKit にあるため）。具象 `HeadingJumpLevelDefaults` は
  `befold/App/` に置き、プロトコルに準拠させる
- **`ViewerRenderer` に具象型を生やさない。** 検索側は
  `ViewerRenderer.swift:81 public var findOptionsPreference: FindOptionsPreference?` で
  読み書きできる具象型を露出しており、これを真似ると「窓が保存値を読み直せる」構造になって
  ユーザー指定の粒度が守られない。レンダラが持つのは記録用プロトコルの参照だけにする

### F3. `FindOptionsPreference` に相乗りしない理由を差し替える
当初案は「意味論が違う（あちらはアプリ全体の単一状態）」としていたが、実測では
`initialFindOptionsScript` の注入点は窓生成時の 1 箇所のみ（`ViewerWebViewFactory.swift:118`）で、
生きている他窓へ配る経路は無い。**振る舞いは既に「次の窓の出発点」で同じ**。
相乗りしない理由は「値の形が違う（Bool 3 個ではなくレベル集合で、未設定を区別する必要がある）」
「検索とジャンプは別の関心」に差し替える。
（`FindOptionsPreference` の doc コメントが実態とずれている件は本タスクのスコープ外）

### F4. `ViewerRenderer` は 392 行 / 閾値 400（余裕 8 行）
当初の見積もりから落ちていた最大のリスク。`makeWebView` の引数は増やさず、
`ViewerWebView.swift:69` が検索で既にやっている「生成後に代入する」形にする。

### F5. 候補の下線は `text-decoration`（文字幅・アクセント色）
h1 / h2 は github-markdown-css が `border-bottom: 1px solid var(--borderColor-muted)` を持つ
（`github-markdown.css:207-213` / `:413-418`）。h3 は持たない。
**「衝突しないこと」ではなく「h1/h2 でも候補かどうか判別できること」が合否基準。**

実測（スナップショット 3 案比較）で決定済み:
- 採用: `text-decoration: underline; text-decoration-color: var(--accent);
  text-decoration-thickness: 2px; text-underline-offset: 3px`（**文字幅**の下線）
- 不採用: `box-shadow` による要素幅の下線 — h1/h2 の既存 border-bottom とほぼ同じ位置に出るため
  「既存の線が青くなった」ようにしか見えず判別できない

`.mmd-jump-current`（outline）と同時に付いたときの見え方は最終形で再度スナップショットを撮る。

### F6. 候補クラスの付け外しは `clearHighlight` を絞り込み点にする
`collect` の呼び出し元は `run()`（open）と `refresh()` の 2 箇所で、`refresh` は
`render()` と `appendChunk()` の末尾から毎回走る。**`refresh` で古い候補のクラスを外さないと
下線が残る**（レベル変更時がまさにこれ）。
`clearHighlight`（`jump.ts:46-53`）で `mmd-jump-current` と `.mmd-jump-target` を
**必ず一緒に**付け外しする。`invalidate` は既存判断（DOM が既に差し替わっているのでクラスは外さず
列だけ捨てる）をそのまま維持する。

### F7. トグル UI の配線は `jump.ts` に置かない
485.1 の決めごと「コントローラ側は列挙の中身を知らない」（`init.ts:41-42` のコメント）を破らない。
`_mmdJump` に `setLevels` のような汎用口を開けると、種類ごとのオプションを通す穴になる。
レベルの状態・トグルの配線・列挙は `jump-providers.ts`（見出しという列挙の関心）に閉じ、
そこから `_mmdJump` へは**再構築の依頼だけ**を投げる。

### F8. 描画中のトグル操作で位置維持を壊さない
`render()` は async で、冒頭の `invalidate()` から着地の `refresh()` までの間 DOM は差し替え途中。
この間にトグルを押してその場で列を作り直すと、着地時の `refresh` が
「差し替え途中の DOM から作った `currentIndex`」を `keptMatchIndex` の入力にしてしまい、
**表示は最終的に正しいのに位置維持の意図だけが静かに壊れる**（TASK-317 / 321 と同型）。

`jump.ts` に描画中を表す内部フラグを置き（`invalidate()` で立て、着地の `refresh()` で下ろす）、
再構築の依頼が描画中に来たらスキップして着地時の `refresh` に任せる。
**判定は DOM の中身の有無ではなく内部フラグで行う**（appendChunk の抑止判定が DOM 判定で
3 回再発した経緯と同じ理由）。

### F9. レベル変更時は先頭へ戻す
レベルを変えると列の同一性が変わり、`keptMatchIndex` で保持した index は別の見出しを指す。
再構築は `refresh(true)`（先頭へリセット）で行う。

### F10. 注入値の適用は `!bar` guard より前
`_mmdInitJump()` は `if (!bar) return;` で早期 return する。`window._mmdInitialJumpLevels` の
適用をこの後ろに置くと、バー要素が無い環境で既定へ静かに縮退する。
find 側の `applyHostSettings` と同じく guard より前で適用し、**(1) レベル状態への反映と
(2) 3 ボタンの `.active` の両方**を設定する（片方だけだと「見た目 ON なのに列は既定」が初回だけ出る）。

### F11. トグルの DOM は `.mmd-find-toggles` を流用しない
`.mmd-find-toggles`（`style.css:583-590`）は `position: absolute; right: 2px` で、
`.mmd-find-input-wrap`（`:559-563`）の `position: relative` を基準にしている。
ジャンプバーには input-wrap が無く `.mmd-find-bar` 自身が `position: fixed` なので、
コンテナクラスを流用すると閉じるボタンと件数表示の上に重なる。
`#mmd-jump-levels` には**専用の非 absolute なコンテナ規則**（`display:flex; gap:2px`）を書く。
**ボタンの皮（`.mmd-find-toggle` と `.active`）だけ共有する**（ジャンプバーは
`class="mmd-find-bar"` を持つので `.mmd-find-bar button` はそのまま当たる）。

### F12. レベルが 0 個のときは truncated ラベルを出さない
3 つとも OFF で 0 件のとき、段階読み込み中だと「0/0（表示範囲内）」と出る。
0 件の原因はフィルタであって表示範囲ではないので事実と食い違う。
**レベルが 0 個のときだけ**ラベルを抑止する（文書に見出しが無いだけの 0 件では、
まだ読んでいない範囲にある可能性があるのでラベルは出したままにする）。

### F13. メッセージ追加で触る箇所（当初の見積もりから落ちていた分）
- `ViewerBridgeMessage.swift`: case 追加、`requiresInteractiveBridging` の網羅 switch、
  `payloadKeys` の網羅 switch、`PayloadKey` 列挙。**検索と揃えて
  `requiresInteractiveBridging == false` 側**に置く（QuickLook でも登録されるが、
  `OneShotRenderer` はストアを nil で渡し、ルータが optional chaining で無害化する既存の形に乗る）
- 契約テスト 2 本が新規に要求する: `declaredMessagesHavePostSites`（バンドルに送信サイトが
  必ず要る）と `payloadKeysMatchDeclaration`（JS と Swift のキー完全一致）
- **`ViewerBridgeContractTests` は 373 行 / 閾値 400（余裕 27）。** 新規 `@Test` を足すと限界に触れるので、
  既存のテーブル駆動テストへの**行追加のみ**に留める

## 実装順序（TDD）

1. Swift: `HeadingJumpLevelRecording`（BefoldKit）+ `HeadingJumpLevelDefaults`（befold/App）と
   その 3 ケーステスト（未設定 → 3 つとも ON / 全 OFF を保存 → 次のインスタンスでも全 OFF /
   一部 ON → そのまま）。**(b) が無いと F1 は「実装した気になるだけ」になる**
2. JS: `jump-providers.ts` にレベル状態を入れ、`HEADING_SELECTOR` を可変にする。
   485.1 のテスト（h1 を目印にしない前提の 6 箇所）を書き換える
3. JS: `clearHighlight` を絞り込み点にして候補クラスを付け外し（F6）、描画中フラグ（F8）
4. HTML/CSS: `#mmd-jump-levels` の 3 ボタンと専用コンテナ規則、`.mmd-jump-target` の下線（F5）
5. JS: トグルの配線（F7）、注入値の適用（F10）、postMessage
6. Swift: メッセージ・ペイロード・ルータ・注入スクリプト・局在化 3 キー（F13）
7. スナップショットで F5 の合否基準（h1/h2 でも候補と分かるか）を確認
8. `docs/dev/native-app-design.md:220` の「h2 / h3」を更新

## 型名について（記録）
`HeadingJumpLevelDefaults` で始める。485.4 で 2 個目のジャンプ設定が要ると分かった時点で
`JumpPreferences` へ統合する。受け皿名で先に作らないのは、2 種類目のトグルが本当に要るかが
未確定なため（E2 の「早すぎる一般化をしない」方針と揃える）。`AppStores` は現在ストア 10 個で、
「アプリ全体で 1 個ずつ持つ永続化ストア一式」という単一の関心の入れ物なので 11 個目を足してよい。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- `viewer-src/jump-providers.ts`: レベル状態・トグルの配線・列挙を集約。jump.ts へは再構築の
  依頼だけを投げ、「コントローラは列挙の中身を知らない」（485.1 の決めごと）を保った。
- `viewer-src/jump.ts`: 候補クラス `.mmd-jump-target` の付け外し、描画中フラグ、
  レベル未選択時の truncated ラベル抑止。
- `BefoldKit/HeadingJumpLevels.swift`: 値型（正規化・保存表現・未設定/空の区別）と、
  読み取り API を持たない `HeadingJumpLevelRecording`、窓へ渡す `HeadingJumpLevelBinding`。
- `befold/App/HeadingJumpLevelDefaults.swift`: 「次に開く窓の出発点」を UserDefaults へ。
- ブリッジ: `jumpLevelsChanged` メッセージと `initialJumpLevelsScript`、局在化 1 キー。

## 設計判断（実装前に決めたもの）

- **保存はキー 1 本。** Bool 3 本だと `bool(forKey:)` が未設定時 false を返すため
  「初回」と「3 つとも OFF」が区別できず、後者が次の窓で既定へ戻る。
  空配列＝全 OFF、キー欠如＝未設定として区別する（前例: `SidebarStateStore.swift:37`）。
- **窓へ渡すのは記録用プロトコルだけ。** 検索の `FindOptionsPreference` は
  `ViewerRenderer` に読み書きできる具象型を露出しており、真似ると「窓が保存値を
  読み直す」構造になる。`SidebarDisplayDefaultsRecording` と同じ形にした。
- **候補の下線は文字幅（text-decoration）。** h1 / h2 は github-markdown-css の
  `border-bottom`（薄いグレー・要素幅）を持つため、要素幅の下線だと「既存の線が
  色付いた」ようにしか見えない。3 案をスナップショットで比較して決定。
- **候補クラスの付け外しは列を捨てる経路が通る 1 関数へ。** 現在位置の付け替えだけは
  別関数（`clearCurrent`）にして候補の印を残す。
- **レベル変更時の再構築は描画中ならスキップ。** 差し替え途中の DOM から作った位置を
  着地時の位置維持が入力にしてしまうため（TASK-317 / 321 と同型）。

## 実機で見つけて直したもの（2 件）

1. **描画中フラグが下りない。** バーを閉じたまま描画すると `invalidate` でフラグが立つが、
   着地の `refresh` はバーが開いているときしか呼ばれない。フラグが残り、以後トグルを
   押しても列が作り直されなかった（見た目だけ変わる）。`open` / `close` で下ろす。
2. **JS と Swift でレベルの表現がずれていた。** JS は数値配列 `[1]` を送り、Swift は
   `["h1"]` を期待。変換に失敗して常に「3 つとも OFF」として保存されていた。
   契約テストはペイロードの**キー名**しか見ないため素通りしていたので、
   両端の表現が一致することを確かめるテストを足した（`ViewerRendererJumpMessageTests`）。

## 行数超過への対処

`ViewerWindowManager` 型グループが 403 行（閾値 400）を超えたため、
`ViewerWindowSessionSync` を独立した型として切り出した（403 → 337）。
ウィンドウの生成・保持と、開閉に伴う記録の追随は別の関心。別コミットにしてある。
`ViewerRendererMessageHandlingTests` の型も 270 行を超えたため、ジャンプ分を
`ViewerRendererJumpMessageTests` へ分けた。

## 型名について（記録）

`HeadingJumpLevelDefaults` で始めた。485.4 で 2 個目のジャンプ設定が要ると分かった時点で
`JumpPreferences` へ統合する。受け皿名で先に作らないのは、2 種類目のトグルが本当に要るかが
未確定なため。

## 検証

- `npm test` 492 件 passed（ジャンプ 34 件）、`swift test` 1623 件 passed。
- swiftlint ベースライン差分ゼロ（54 件）、`check-type-group-size.sh --check` 通過、
  oxlint / oxfmt / 循環 import / typecheck クリーン、en/ja 翻訳漏れなし、
  webview スモーク通過、markdownlint 0 件、`check-doc-symbols.sh` 通過。
- **実装を戻すと落ちることを実測した項目**: 未設定と全 OFF の区別、描画中フラグの解除。
- **実機（Debug ビルド）**: 3 つとも ON で 5 件・候補すべてに下線、H1 を OFF にすると
  1/2 へ更新し h1 の下線が消える、保存値が `(h2, h3)` になる、アプリ再起動後も
  H1 消灯・H2/H3 点灯・1/3 で復元される。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
見出しジャンプに h1 を加え、h1/h2/h3 を選ぶトグルと、バーを開いている間だけ候補を下線で示す表示を付けた。トグルの状態はライブ値が窓ごと・保存値が次に開く窓の出発点（SidebarDisplayDefaults と同じ形）で、窓へ渡すのは読み取り API を持たない記録口だけにして粒度を構造で守った。設計レビューで保存形式の穴（未設定と全 OFF が区別できない）を着手前に潰し、実機検証で 2 件のバグ（描画中フラグの残留、JS と Swift の表現ずれ）を見つけて直した。npm 492 / swift 1623 件 passed、実機で保存と再起動後の復元まで確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
