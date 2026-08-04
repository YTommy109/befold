---
id: TASK-274
title: テストの前提が環境依存になっている箇所を直す（macOS 14 / weak 参照）
status: To Do
assignee: []
created_date: '2026-08-03 15:23'
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
- [ ] #1 macOS 14 でも swift test が green になる（裏打ちのアサートが環境で切り分けられている、または不変条件だけを見ている）
- [ ] #2 WKWebView をテスト内で強参照して寿命を明示している
- [ ] #3 変更後も、バイト列保存・等値・ハッシュ一致の検証は失われていない
<!-- AC:END -->
