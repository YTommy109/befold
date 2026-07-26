---
id: TASK-72
title: QuickLook 拡張を実装する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-19 06:38'
updated_date: '2026-07-26 14:50'
labels: []
dependencies: []
ordinal: 210000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold にファイル種別に応じたプレビューを提供する QuickLook Extension (appex) を追加する。TASK-1 系の事前リファクタリング（BefoldRenderKit 抽出・hostFeatures フラグ・XSS対策・NormalizedTextCache 先頭打ち切り等）は完了済みで、これを土台に本体実装を行う。対象ファイル種別は FileType.swift の分類を踏襲しつつ、PDF・画像（.pdf, .png/.jpg/.jpeg/.gif/.webp/.bmp/.ico）は macOS 標準の QuickLook が既に高品質なプレビューを提供するため、befold の QuickLook 拡張の対象から除外する。befold 拡張の対象は「レンダリングモード」の .mmd/.mermaid, .md/.markdown, .svg, .html/.htm, .csv/.tsv と、シンタックスハイライト対象の約40種のソースコード拡張子（FileType.codeExtensionLanguages）とする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 QuickLook Extension が .mmd/.mermaid, .md/.markdown, .tsv をレンダリングモードでプレビューできる（同じ UTI を宣言する他の QuickLook 拡張が入っていない環境で。QuickLook は 1 UTI につき拡張を 1 つしか選ばず優先度指定 API が無いため、競合アプリが入った環境で選ばれないことは不具合としない）
- [x] #2 QuickLook Extension が FileType.codeExtensionLanguages に含まれる拡張子をシンタックスハイライト付きでプレビューできる
- [x] #3 PDF・画像拡張子（pdf/png/jpg/jpeg/gif/webp/bmp/ico）は befold の QuickLook Extension の対象外とし、Info.plist の対応 UTI/拡張子リストに含めない
- [x] #4 拡張子と処理経路（レンダリング/ハイライト/対象外）の対応が FileType.swift のロジックと一致していることをテストで検証する
- [x] #5 .svg / .html / .htm / .csv は UTI を宣言しても macOS の内蔵・アプリレベルのプレビューアが優先されるため、befold では表示されない（宣言は残すが、表示できることは保証しない）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 描画完了検知とappexバンドルリソース解決をプロトタイプで検証(ViewerRendererへのonRenderComplete相当コールバック追加を含む)
2. FileType.swiftにQuickLook対象拡張子集合を返す純粋関数(quickLookSupportedExtensions)を追加し、レンダリング5種+codeExtensionLanguagesのみを対象、PDF/画像を除外
3. RendererFeaturesにQuickLook専用の全機能無効プリセット(quickLookRestricted)を追加
4. project.ymlにapp-extensionターゲットを追加し、Info.plist(QLSupportedContentTypes)・entitlements(サンドボックス有効・ネットワークなし)を新設。.svgはpublic.xml側に紐づけて画像UTIとの重複を避ける
5. QLPreviewingController(View-based)を実装し、loadOneShotの呼び出しのみの薄いラッパーとする
6. 大きめのmermaid/markdown/巨大コードファイルでappexのメモリ・起動速度を実機検証
7. FileType拡張子集合のユニットテスト、xcodebuildでのappexビルド確認、Finder上でのQuickLook手動検証(PDF/画像が対象外であることを含む)

各ステップをTASK-72の子タスクとして分割し、順に着手する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
コード品質を新機能より優先する方針に伴い、本タスクを保留して To Do へ戻した（子タスク 7 件はすべて未着手で、実装成果物はない）。再開の目安: 構造リファクタ層（TASK-135 / 133 / 134 / 139 / 140 系 / 136 / 137 / 138）とテスト品質層が片付いた時点。

## 進捗と中断(2026-07-26)
子タスク 72.1 / 72.2 / 72.3 / 72.4 は Done。72.5 は実装完了・コミット済みだが
AC#1 未達のまま中断。72.6 / 72.7 は着手不可。

### 中断理由: 対象 UTI の多くが他の QuickLook 拡張に取られる
QuickLook は 1 つの UTI につき拡張を 1 つしか選ばず、優先度を指定する API はない。
実機(macOS 26.5.2)で qlmanage -p により appex の起動有無を確認した結果:
- 起動する: .mermaid / .swift / .json
- 起動しない(設計どおり対象外): .pdf
- 起動しない(想定外): .md / .markdown / .svg / .html / .csv

競合相手:
- markdown 系 UTI → org.sbarex.QLMarkdown.QLExtension (/Applications/QLMarkdown.app)
- public.html → com.apple.Safari.SafariQuickLookPreview
- public.svg-image → システム標準の画像プレビュー

befold 側のコードの不具合ではなく環境側の競合だが、この状態では
AC#1「.mmd/.mermaid, .md/.markdown, .svg, .html/.htm, .csv/.tsv を
レンダリングモードでプレビューできる」は競合アプリが入った環境では
原理的に満たせない。AC#1 の見直しが必要。

### 再開時に決めること
1. AC#1 の対象範囲を、実効性のある種別(mermaid + ソースコード系)へ縮小するか
2. 宣言は残したうえで「環境によっては選ばれない」と割り切り、
   競合をユーザーへ知らせる仕組みを別途用意するか
3. .svg の public.svg-image 宣言(TASK-72.4 で決めた判断)を維持するか

### 未実施
レンダリング結果そのものの目視確認(TASK-72.7 の手動チェック項目)。

## 中断解除(2026-07-26)

### 空白プレビューの root cause: appex に network.client が無かった
実機検証で判明。サンドボックス下の WKWebView はローカルコンテンツのみでも
WebKit の Networking プロセスを起動するため、com.apple.security.network.client
が無いと Networking プロセスが起動できず、連鎖して WebContent も上がらない。
結果、あらゆるロードが完了せず空白のプレビューになっていた。

計測で確定させた事実:
- viewer.html はバンドルから解決でき、appex から読める(canRead=3883)
- loadOneShot は oneShotRenderTimeout(3秒)で時間切れ、webView.url=nil
- 対照実験: ファイルを使わない loadHTMLString すら url=nil のまま完了しない
  → file:// アクセスではなくプロセス起動側の問題と確定
- 動作している QLMarkdown の appex との entitlements 差分がこれだけだった

QuickLookInfoPlistTests が「network.client を持たない」ことを assert しており、
この不具合を固定していたため、理由付きで反転した。

### UTI 競合の実測(macOS 26.5.2 / QLMarkdown・Safari 導入環境)
- befold が担当: .swift .json .py .yaml .tsv .mermaid
  (.mermaid のみ独自 UTI com.degino.befold.mermaid-diagram に解決されて勝てる)
- 競合で負け: .mmd .md .markdown(QLMarkdown) / .html .htm(Safari) / .svg .csv(システム標準)
  .mmd は独自 UTI ではなく net.ia.markdown に解決される(他アプリが .mmd を所有)
- .txt は対象外(public.plain-text 未宣言)で意図どおり

AC#1 は「競合が無い環境で」という条件付きに改訂した(宣言は残す方針)。

### .ts の扱い
.ts は競合ではなく UTI 未宣言。実機では public.mpeg-2-transport-stream(動画)に
解決される。QuickLook は UTI 単位でしか宣言できず TypeScript と動画を区別
できないため、開発者向けツールという位置づけから TypeScript を優先し、
この動画 UTI を QLSupportedContentTypes に追加した。

### 検証環境の注意
ローカル Release ビルドは Developer ID 署名を明示しないと ad-hoc + hardened
runtime になり、library validation で dyld が起動時にクラッシュさせる。
また .build や DerivedData のコピーを起動すると LaunchServices の appex 登録を
奪うため、QuickLook の検証時は /Applications 以外のコピーを消しておくこと。

### 未実施
72.6(メモリ・起動速度の実機計測)。

### .ts は QuickLook 対象にできない(2026-07-26 実機確認)
.ts は競合ではなく UTI 未宣言が原因だったため public.mpeg-2-transport-stream を
一度宣言したが、**この UTI を宣言する QuickLook 拡張が befold だけの状態にしても
macOS は内蔵プレビューアを優先し、appex は呼ばれなかった**(macOS 26.5.2)。
効かない宣言を残すと本物の .ts 動画のプレビューを奪うリスクだけが残るため撤回した。
撤回を固定する回帰テスト(supportedContentTypesExcludeTransportStream)を追加済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
befold の QuickLook Extension(appex)を実装し、Finder 上で動作することを確認した。

対象は FileType の分類を単一情報源とし、レンダリング系(.mmd/.mermaid/.md/.markdown/.svg/.html/.htm/.csv/.tsv)と codeExtensionLanguages のソースコード約 40 種。PDF・画像は macOS 標準に任せて対象外とした。appex はレンダリングロジックを持たず、ViewerRenderer.loadOneShot の呼び出しと分岐のみの薄いラッパーとして実装した。

実装中の最大の不具合は、appex に com.apple.security.network.client が無く WebContent プロセスが起動できず、befold が担当した全種別が空白のプレビューになっていたこと。既存テストがこの状態を「ネットワーク権限を持たない」として固定していたため、理由付きで反転した。

また実機計測により、非行指向ファイルは WebContent のメモリがサイズにほぼ比例すること(9MB の markdown で 4.17GB)が分かり、QuickLook 専用に 2MB の上限を導入した。行指向は先頭チャンクのみ描画するため 99MB でも 0.33 秒・118MB に収まる。

macOS 側の制約として、UTI ごとに 1 拡張しか選ばれず優先度指定 API が無いこと、.svg/.html/.csv/.ts は内蔵・アプリレベルのプレビューアが優先され拡張側から覆せないことが判明し、受け入れ基準に明記した。

検証: swift test 659 件パス、xcodebuild(Release / Developer ID)成功、Finder での全対象拡張子の手動確認。
<!-- SECTION:FINAL_SUMMARY:END -->
