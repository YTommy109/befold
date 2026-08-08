---
id: TASK-356
title: プレビューの表示モード切替を 3 セグメント + レイアウトトグルにし cmd+1〜4 を割り当てる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 01:35'
updated_date: '2026-08-08 10:53'
labels: []
dependencies: []
priority: medium
ordinal: 615000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
プレビューエリアの表示モードの発見性を上げる。現在ツールバーには「レンダリング / ソース」の 2 セグメント（`ViewerToolbarController.swift:122-130`）しかなく、差分表示と差分左右分割は View メニューからしか辿れない（`MainMenuBuilder.swift:279-293`）ため、機能の存在が伝わっていない。

## 採用する UI（案 A）

第 1 階層を 3 択セグメント、第 2 階層のレイアウトを従属コントロールにする。

```
[ レンダリング | ソース | 差分 ]   [レイアウト]
      cmd+1       cmd+2    cmd+3      cmd+4
```

- 「差分」セグメントを選ぶと、内部的にソース表示 ON + 差分 ON になる
- 上下（`inline`）/ 左右（`sideBySide`）の切替は独立した小さなトグルとし、差分を選んでいない間は**無効化する**（出現・消滅させるとツールバー幅が動くため。この判断は暫定で、実装時に見直してよい）

この形を選んだ理由は、状態が対等な 4 択ではなく階層構造だから。差分はソース表示中でないと不可（`ViewerCapabilities.swift:61` `canToggleDiff`）、レイアウトは差分 ON でないと不可（`ViewerWindowController.swift:832-835`）であり、実装済みの従属関係を UI に写像する。cmd+1〜4 のフラットな 4 連セグメントはこの階層を潰すため採らない。

## 記憶の粒度をファイル単位に揃える

現状、ソース表示は**ファイルごと**（`SourceModeStore.swift:11`、キー `ViewerSourceModes`）、差分 ON/OFF と差分レイアウトは**アプリ全体**（`DiffDisplayPreference.swift:4-12`、キー `SourceDiffEnabled` / `SourceDiffLayout`）で粒度が食い違っている。差分を第 1 階層のモードに昇格させるとこの矛盾が表面化する（ファイル A で差分を選び B へ移ると、B はレンダリング表示なのに差分フラグだけ立つ）。

本タスクで**差分 ON/OFF をファイル単位の記憶に変更する**。レイアウトの粒度も揃えるかは実装時に判断してよい（レイアウトは好みの設定でありアプリ全体が自然という考え方もある）。

なお「アプリ単位でモードを固定する」機能は別タスクで扱う。

## 付随して解消できる歪み

差分表示は現在 cmd+D、差分左右分割は shift+cmd+D に割り当てられている（`MainMenuBuilder.swift:281,287`）。cmd+D はブックマークと衝突しており、dev ビルドではブックマークを cmd+B へ逃がす分岐がある（`BookmarkShortcut.swift:23`）。差分を cmd+3 / cmd+4 へ移せば cmd+D が空くため、この分岐を撤去してブックマークのキーをビルド種別によらず一本化できる。

**未決定**: 一本化後のブックマークを cmd+D と cmd+B のどちらにするか。dev ユーザーの操作感を変えない cmd+B が無難だが、stable の既存ユーザーは cmd+D に慣れている。着手時にユーザーへ確認すること。

## 制約

- 差分表示・差分左右分割は `FeatureGate.isSourceDiffEnabled` 配下（`FeatureGate.swift:61`）。**stable ビルドでは 3 つ目のセグメントとレイアウトトグルが出ず、現状どおり 2 セグメントになること。** コミットには `(gate)` スコープを付ける
- `FeatureGate.swift` の露出点 doc コメントの列挙を更新する（`befoldTests/FeatureGateEnumerationTests.swift` がソース走査で検証している）
- cmd+1〜4 は現在未使用（数字キーは `MainMenuBuilder.swift:162` の cmd+0 = 実寸のみ）。衝突はない
- ショートカットの Help 表示はメニュー定義から自動生成される（`MenuShortcutCatalog.swift:37-47`）ため個別対応は不要
- 状態の持ち方を変える変更に当たるため、実装着手前に `/review-design` を 1 回回し、結果を Implementation Plan に反映すること
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ツールバーのモードセグメントが dev ビルドで「レンダリング / ソース / 差分」の 3 択になる
- [x] #2 stable ビルド（FeatureGate OFF）ではセグメントが従来どおり 2 択のままで、レイアウトトグルも現れない
- [x] #3 差分レイアウトの切替コントロールが、差分を選んでいない間は無効になっている
- [x] #4 cmd+1 / cmd+2 / cmd+3 でそれぞれレンダリング・ソース・差分に切り替わる
- [x] #5 cmd+4 で差分レイアウトが上下と左右で切り替わる
- [x] #6 差分の ON/OFF がファイル単位で記憶され、別ファイルへ移っても差分状態が引き継がれない
- [x] #7 ブックマークのショートカットが dev ビルドと stable ビルドで同一になり、BookmarkShortcut のビルド種別分岐が撤去されている
- [x] #8 FeatureGate.swift の露出点 doc コメントが更新され FeatureGateEnumerationTests が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー結果（/review-design 実施済み）

単純化の検討: per-file の差分フラグを新設せず、SourceModeStore の payload を
ViewerDisplayMode { rendered, source, diff } の 1 値へ統合する。2 つの Bool だと
「差分 ON かつレンダリング表示」という不整合が表現可能になるため（現状は
ViewerWindowController+Diff.swift:24 の guard が実行時に握り潰しているだけ）。
状態は増えず、DiffDisplayPreference.isEnabled が 1 つ減る。

レビューで方針を変えた点:
- A: ViewerDisplayMode はアプリ層に閉じ、RenderKit 境界は isSourceMode:Bool + DiffState? のまま
  （ViewerRenderer.swift:119 ほか RenderKit 全体と QuickLook が Bool 前提）
- B: A の帰結としてスクロール位置キー（ViewerWindowController.swift:652-656）は
  .source と .diff で共有される。これが正しい（差分は同じソース表示上のオーバーレイ）
- C: isEnabled の消費経路は 4 箇所。ViewerContentView.swift:35 が漏れていた。
  差分表示中フラグは ViewerStore へ持たせ、ViewerContentView は layout のみ参照する
- D: 非同期着地時ガード（+Diff.swift:41）を「着地時点でも .diff か」に更新し、
  .diff を離れるときの store.diffText クリア（開始時の無効化）も経路として置く
- E: DiffDisplayPreference のデフォルト引数（ViewerWindowManager.swift:87 /
  ViewerWindowController.swift:149）を撤去し必須引数にする（TASK-319 の再発防止＝構造で担保）
- F: セグメント添字を enum rawValue に直結させず、可視セグメント配列で解決する

ユーザー判断:
- ブックマークは cmd+D に一本化
- cmd+U は残す（撤去は AC 外）
- 差分レイアウトはアプリ全体の粒度のまま
- 旧キー ViewerSourceModes は新キーへ移行する（記憶を失わせない）

## 手順

1. ViewerDisplayMode（String RawRepresentable, rendered/source/diff）を追加
2. SourceModeStore → DisplayModeStore へ改名し PathKeyedDictionary<String> 化。
   新キー ViewerDisplayModes、旧キー ViewerSourceModes からの片方向移行を入れる。
   restoredDisplayMode は FileType 能力と FeatureGate で降格（source 非対応→rendered、
   diff 非対応/ゲート OFF→source）。PerFileStateStore を追随
3. DiffDisplayPreference を layout のみに縮小（isEnabled と SourceDiffEnabled キーを削除）。
   デフォルト引数を撤去。ViewerWindowManager.toggleSourceDiff と delegate hook を撤去
4. ViewerStore に差分表示中フラグを追加し、ViewerContentView をそれに繋ぎ替える
5. ViewerWindowController: setSourceMode(Bool) → setDisplayMode(ViewerDisplayMode) へ一本化。
   isSourceMode は displayMode != .rendered の computed。CLI の sourceModeOverride も追随。
   capabilities に canSelectDiffMode / canToggleDiffLayout を追加し menu validation と共用
6. ViewerToolbarController: 可視セグメント配列で 3 択（ゲート OFF なら 2 択）を構築。
   レイアウトトグルを独立ツールバー項目にし、.diff 以外では無効化
7. MainMenuBuilder: cmd+1/2/3（モード）+ cmd+4（レイアウト）。cmd+D/shift+cmd+D 撤去。
   cmd+U は残す。BookmarkShortcut のビルド種別分岐を撤去し常に "d"
8. FeatureGate.swift の露出点 doc 列挙を更新（FeatureGateEnumerationTests が集合一致を検証）
9. Localizable.xcstrings にキー追加（既存の並び順を保ち近縁キーの直後へ挿入）
10. テスト: 3 値往復と降格、ファイル A=.diff / B=.rendered の往復で差分が引き継がれないこと
    （AC#6 を破ったら落ちる）、メニューのキーテーブル、ゲート OFF でのセグメント数
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 検証記録

- ユニット/全テスト: `swift test` 1203 件パス（新規 11 件を追加）
- `.app` ビルド: `xcodebuild build -scheme befold` BUILD SUCCEEDED
- swiftformat: 全ターゲット 0 files require formatting
- swiftlint: origin/main とのベースライン差分に**新規ルール違反ゼロ**
  （既存違反の行数が増減しただけ。途中で出た opening_brace / MainMenuBuilder の
  type_body_length / cyclomatic_complexity の 3 件は、多行条件の解消・モード→文言対応の
  ViewerDisplayMode への移動・validateDisplayModeItem への切り出しで解消済み）
- markdownlint: 0 issues
- 翻訳: en/ja とも未翻訳 0 件、未定義キー参照 0 件
- 実機（dev/DEBUG ビルド, AX 経由）:
  - View メニューが Show Rendered[1] / Show Source[2] / Show Changes[3] /
    Show Diff Side by Side[4] / Bookmark[D] を持つ
  - cmd+1/2/3 でチェックが排他的に移動、cmd+4 でレイアウトが往復
  - 差分を選んでいない間は Show Diff Side by Side が enabled=false（AC#3）
  - ツールバーのスクリーンショットで 3 セグメント + レイアウトトグルを確認

## AC#2（stable で 2 択）の担保方法

Release ビルド自体は成功したが、この環境では署名の Team ID 不一致
（`Library not loaded: @rpath/BefoldKit.framework` / different Team IDs）で
起動できず、実機での確認はできなかった。代わりにゲート判定を注入可能な純粋関数
（`ModeSegments.modes(isSourceDiffEnabled:)` /
`MainMenuBuilder.addDisplayModeItems(to:isSourceDiffEnabled:)`）へ切り出し、
`displayModeExposureFollowsGateInBothDirections` で OFF 側も含めた両方向を検証している。
OFF 分岐が壊れたらこのテストが落ちる。

## 実装中に見つけて直した設計上の問題（レビュー後に判明した分）

1. `canSelectDiffMode` を「いまソース相当を出しているか」で判定すると、レンダリング表示中に
   cmd+3 が押せない（一度 cmd+2 を経由しないと差分へ行けない）。差分を選ぶこと自体が
   ソース表示へ移る操作なので、種別（`!isBinaryContent && supportsDiffDisplay`）で判定する形に変えた。
2. `.code` 種別は `supportsSourceMode == false` のため、降格ルールを `.source` と共通化すると
   コードファイルの差分が復元されない。`.diff` の可否を `supportsDiffDisplay` + ゲートで
   独立に判定する形にした（テストが落ちて気付いた）。
3. `.code` 種別は保存モードが `.rendered` でも実際にはソースを出しているため、選択位置を
   `displayMode` 直結にすると「選べないレンダリングセグメントが選択済み」に見える。
   表示用の導出 `ViewerStore.effectiveDisplayMode` を足した。
4. リネーム時の降格を「supportsSourceMode でなければレンダリングへ」と書き下すと 2 と同型の
   バグを 2 箇所に持つことになるため、`restoredDisplayMode` の 1 経路へ寄せて
   `resetDisplayMode()` を撤去した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
プレビューの表示モード切替を「レンダリング / ソース / 差分」の 3 択セグメント + 独立した
差分レイアウトトグルにし、cmd+1〜cmd+4 を割り当てた。差分が cmd+D を空けたため、
ブックマークのビルド種別分岐（dev は cmd+B / stable は cmd+D）を撤去し cmd+D に一本化した。

単純化: per-file の差分フラグを新設せず、per-file の永続値を ViewerDisplayMode
（rendered / source / diff）の 1 値へ統合した（SourceModeStore → DisplayModeStore、
新キー ViewerDisplayModes、旧キー ViewerSourceModes から 1 度だけ移行）。これにより
DiffDisplayPreference.isEnabled とアプリ全体キー SourceDiffEnabled が消え、
「レンダリング表示なのに差分だけ ON」という不整合が状態として表現できなくなった
（この不変条件は型が保証するのでテスト不要）。DiffDisplayPreference はレイアウトのみに
縮小し、粒度を構造で守るためデフォルト引数を撤去して必須引数にした（TASK-319 の再発防止）。
3 値はアプリ層に閉じ、BefoldRenderKit / QuickLook 境界は従来どおり isSourceMode:Bool +
DiffState? のまま（差分の有無は既に DiffState? が表現している）。

検証: swift test 1203 件パス（新規 11 件）、xcodebuild build -scheme befold 成功、
swiftformat 0 件、swiftlint は origin/main とのベースライン差分で新規ルール違反ゼロ、
markdownlint 0 件、翻訳漏れ 0 件。dev ビルドを AX 経由で操作し cmd+1/2/3 の排他切替・
cmd+4 のレイアウト往復・差分未選択時のレイアウト無効化・3 セグメントのツールバー表示を実測。
stable 側（ゲート OFF）は Release バンドルが署名の Team ID 不一致で起動できなかったため、
ゲート判定を注入可能な純粋関数へ切り出し両方向をテストで担保した。
<!-- SECTION:FINAL_SUMMARY:END -->
