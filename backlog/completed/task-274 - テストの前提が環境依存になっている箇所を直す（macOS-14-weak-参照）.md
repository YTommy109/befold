---
id: TASK-274
title: テストの前提が環境依存になっている箇所を直す（macOS 14 / weak 参照）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-03 15:23'
updated_date: '2026-08-04 01:45'
labels:
  - test
dependencies: []
priority: low
ordinal: 465000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review high の指摘 2 件。

## 1. macOS 14 では落ちるアサート（CONFIRMED）
URLNativeBackedFileURLTests.swift:44 / :60 の `#expect(rebuilt.path.isContiguousUTF8)` と FileListEntryTests.swift:36-37 の `#expect(entry.url.path.isContiguousUTF8)` / `#expect(entry.pathKey.isContiguousUTF8)` は、TASK-269 で実測したとおり macOS 14 では成立しない（あちらでは URL 実装が異なり nativeBackedFileURL は no-op になる。ただし遅い経路自体が無いので実害はない）。Package.swift と project.yml は macOS 14 を deployment target に宣言しているが CI は macos-26 のみのため、macOS 14 の手元でテストを回した人だけが 3 件の赤を踏む。

対処は「裏打ちのアサートを OS 判定で切り分ける」か「全対応 OS で成り立つ不変条件（バイト列の保存・等値・ハッシュ一致）だけを見る」のどちらか。

## 2. weak プロパティへ一時オブジェクトを代入している（PLAUSIBLE）
WebViewCommandControllerTests.swift:31 の `proxy.webView = WKWebView()` は、WebViewProxy.webView が `public weak var` のため強参照の持ち主がいない。現状は autorelease で生きているだけで、release ビルドや将来の WebKit 変更で nil になれば、無関係な理由で `#expect(controller.canOperateOnVisibleDocument)` が落ちる。テスト内でローカル変数に持たせて寿命を明示する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 macOS 14 でも swift test が green になる（裏打ちのアサートが環境で切り分けられている、または不変条件だけを見ている）
- [x] #2 テストが weak プロパティへ一時オブジェクトを代入して寿命を運任せにしている箇所がない
- [x] #3 変更後も、バイト列保存・等値・ハッシュ一致の検証は失われていない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 着手前の前提検証（2026-08-04）
指摘 2（weak プロパティへ一時オブジェクトを代入）は**既に解消済み**だった。起票時に指した WebViewCommandControllerTests.swift:31 の `proxy.webView = WKWebView()` は、TASK-276（ADR 0002 段 4 / DocumentRendering port）で FakeDocumentRenderer へ置き換わっており、現在このテストは WKWebView を一切生成しない。リポジトリ全体でも weak な WebViewProxy.webView へ代入するテストは残っていない（`rg 'WebViewProxy' --glob '*.swift' | grep -i test` が 0 件）。テスト内の `= WKWebView()` は ViewerRendererContentUpdateTests / ViewerRendererVisibilityTests の 2 箇所だけで、代入先の ViewerRenderer.webView は **strong な var** のため寿命は明示されている。AC #2 は「weak へ一時オブジェクトを代入している箇所がない」という現状を確認する形へ書き換えた。

## 実装（指摘 1）
バージョン境界での分岐（`if #available(macOS 15, *)`）ではなく、**実際の挙動を測る能力プローブ**にした。TASK-269 で実測したのは macOS 14 と 26 の 2 点だけで、その間のどこで URL の実装が変わったかは確かめていない。境界を推測して書くと、外れたときに間違った側で黙って検証を飛ばす。

BefoldTestSupport/URLBackingSupport.swift を新設し、`rebuildYieldsContiguousUTF8` が「FileManager 由来の非 ASCII 名 URL を fileSystemRepresentation から作り直したとき、パスが連続 UTF-8 になるか」を 1 度だけ判定する。裏打ちを見る 4 つのアサート（URLNativeBackedFileURLTests :44 :60、FileListEntryTests :36-37）をこの判定で囲った。

プローブは `URL(fileURLWithFileSystemRepresentation:)` を直接叩くので、`nativeBackedFileURL` が将来 no-op へ退行しても macOS 26 では true のまま → アサートが走って落ちる。検証力は落ちていない。判定できない場合（一時ディレクトリが作れない等）は true を返し、黙って飛ばすより落とす側に倒している。

## 検証
- 手元（macOS 26.6）でプローブが true を返すことを一時テストで確認（＝アサートが空振りしていない）。確認後に一時テストは削除。
- swift test 1037 tests green / swiftlint 77 件（main のベースラインと同数、変更ファイルに指摘なし）/ xcodebuild 成功。
- macOS 14 実機は無いため未実行。ただし判定が OS バージョンではなく挙動由来になったため、no-op の環境では 4 つのアサートが自動的に外れる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
裏打ち（連続 UTF-8）を見る 4 つのアサートを、OS バージョン判定ではなく実挙動の能力プローブ（BefoldTestSupport.URLBackingSupport）で囲い、macOS 14 のように nativeBackedFileURL が no-op になる環境では自動的に外れるようにした。プローブは URL(fileURLWithFileSystemRepresentation:) を直接測るため、実装が no-op へ退行すれば macOS 26 では従来どおり赤になる。バイト列保存・等値・ハッシュ一致の検証は無条件のまま残した。指摘 2（weak への一時オブジェクト代入）は TASK-276 の port 導入で既に解消済みで、現在リポジトリに該当箇所が無いことを確認。手元でプローブが true を返すことを一時テストで確かめたうえで削除し、swift test 1037 green / swiftlint 77 件（ベースライン同数）/ xcodebuild 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
