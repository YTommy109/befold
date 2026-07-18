---
id: TASK-1.11
title: QuickLook 経路で SHA256 全量ハッシュ・エンコーディング全量再スキャンをスキップする
status: Done
assignee:
  - '@tommy109'
created_date: '2026-07-18 13:41'
updated_date: '2026-07-18 23:45'
labels: []
dependencies:
  - TASK-1.8
parent_task_id: TASK-1
priority: medium
type: enhancement
ordinal: 1150
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
パフォーマンスレビュー（2026-07-18）で発見（推奨）。(1) NormalizedTextCache.dataHash（:30-33）の SHA256.hash(data:) は ViewerStore.apply() のライブリロード同一内容スキップ専用（ViewerStore.swift:268,282）で、1回描画の QuickLook では 100MB 全走査が純粋な無駄。(2) TextEncoding のフォールバック（TextEncoding.swift:112, :73）は『UTF-8 デコード不可 かつ 先頭8KBのレガシー判定でも未確定』のときのみ NSString.stringEncoding を 100MB 全体に実行し、該当すると QuickLook 応答が秒単位まで伸びうる。QuickLook 経路では dataHash をスキップし、エンコーディング判定窓を先頭 N バイトに制限する。task-1.8 の先頭打ち切り読込と併せて対応するのが自然。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 静的1回読込（QuickLook）経路で dataHash 計算が行われない
- [x] #2 エンコーディング判定のフォールバック全量スキャンが先頭Nバイトに制限される
- [x] #3 アプリ本体のライブリロード同一内容スキップに回帰がない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. NormalizedTextCache.init に oneShotLoad: Bool = false を追加。dataHash の型を Int から Int? に変更し、oneShotLoad: true では SHA256 計算自体を省略して nil にする(既定 false は従来どおり)
2. TextEncoding.detectAndDecodeText に fallbackScanLimit: Int? = nil を追加。2回目のレガシーエンコーディング判定窓を、既定(nil)では従来どおり全データ、指定時は data.prefix(limit) に制限する。復号(decode)自体は常に全データに対して行うため正しさは変わらない
3. TextEncoding.oneShotFallbackScanBytes(1MiB)を新設し、NormalizedTextCache が oneShotLoad: true のときだけこの値を fallbackScanLimit として渡す
4. ViewerLoadPipeline.load に oneShotLoad: Bool = false を追加し、chunked/full 両分岐の NormalizedTextCache 生成に伝播する。ViewerStore は既定の false のまま呼び出すため main app の挙動は変わらない
5. contentHash(ViewerStore)は元々 Int? のため dataHash の型変更は無改修で互換
6. テスト: NormalizedTextCacheTests に oneShotLoad の hash 省略・従来デコード継続の3件、TextEncodingTests に fallbackScanLimit が実際に効いている(ASCIIヘッダーが oneShotFallbackScanBytes 超のケースで oneShotLoad: true が decodeFailed になり、false は成功する)ことを示す2件、新規 ViewerLoadPipelineTests に chunked/full 両経路での dataHash nil 化とデフォルト時の非回帰を示す3件を追加
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: swift test 全体(392件、新規8件含む)が通過。新規テスト:
- NormalizedTextCacheTests: oneShotLoadSkipsHash(dataHash==nil)/defaultLoadStillComputesHash(回帰なし)/oneShotLoadStillDecodesCorrectly(デコード・正規化は従来どおり)
- TextEncodingTests: ASCIIヘッダーが oneShotFallbackScanBytes(1MiB)超のケースで、oneShotLoad:false(既定)は全量フォールバックで正しくデコードできる(回帰なし)一方、oneShotLoad:true は decodeFailed になることを示し、フォールバック判定窓が実際に制限されていることを直接証明した
- ViewerLoadPipelineTests(新規ファイル): ViewerLoadPipeline.load(oneShotLoad:true) が chunked/full 両方の outcome で cache.dataHash==nil になること、oneShotLoad未指定(既定)では従来どおり dataHash が計算されることを ViewerStore を介さず直接検証
実装は ViewerStore からは一切呼ばれない(oneShotLoad の既定値 false のまま main app は動作)ため、AC3(ライブリロード同一内容スキップへの回帰なし)は型変更(dataHash: Int→Int?)後も contentHash: Int? との比較が無改修で成立することと合わせて確認した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NormalizedTextCache.init に oneShotLoad: Bool(既定 false)を追加し、true の場合は (1) SHA256 dataHash 計算を省略(nil を返す)、(2) TextEncoding のレガシーエンコーディング判定フォールバックを全データではなく先頭 oneShotFallbackScanBytes(1MiB)に制限するようにした。ViewerLoadPipeline.load にも同名パラメータを追加し、chunked/full 両分岐へ伝播させた(QuickLook 拡張のような1回描画ホストが今後利用できる経路として準備、既定 false のため main app/ViewerStore の挙動は変わらない)。dataHash の型は Int から Int? に変更したが、ViewerStore.contentHash が元々 Int? のため呼び出し側の修正は不要だった。
検証: swift test 全体392件(新規8件含む)通過。ASCIIヘッダーが oneShotFallbackScanBytes を超えるレガシーエンコーディングファイルで、oneShotLoad:false は従来どおり全量フォールバックで正しくデコードでき(回帰なし)、oneShotLoad:true はデコードに失敗する(=フォールバック窓が実際に制限されている)ことを対で確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
