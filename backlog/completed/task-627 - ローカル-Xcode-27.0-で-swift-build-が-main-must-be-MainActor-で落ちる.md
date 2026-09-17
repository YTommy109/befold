---
id: TASK-627
title: ローカル Xcode 27.0 で swift build が main() must be '@MainActor' で落ちる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-09-16 00:36'
updated_date: '2026-09-16 01:11'
labels:
  - build
dependencies: []
priority: high
type: bug
ordinal: 824000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
clean な作業ツリー（HEAD c2bea481）で `swift build` が次のエラーで落ちる。

```
BefoldApp/befold/App/AppDelegate.swift:73:29: error: main() must be '@MainActor'
    nonisolated static func main() {
```

実測（2026-09-16）:
- ローカル: Xcode 27.0（27A266a）/ Apple Swift 6.4
- CI ピン: 26.6（`.github/workflows/ci.yml` と `release.yml`）
- ローカルには Xcode 27.0 しか無く、`xcode-select` で古い方へ戻せない

Swift 6.4 が `nonisolated static func main()` を許さなくなったことによるツールチェーンずれ。TASK-619 と同型（Xcode の自動アップデートでローカルが CI ピンより先に進む）。

`@MainActor` を付ける 1 行修正で通る見込みだが、CI ピン（26.6）側でも通ることを確認してから入れること。あわせて CI ピンを 27.0 へ上げるかどうかも決める。

編集ごとの PostToolUse フックが `swift build` / `swift test` を回すため、この状態では Swift ファイルの編集が全てフック失敗になる（実害あり）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ローカル（Xcode 27.0 / Swift 6.4）で swift build が通り、Swift ファイル編集時の PostToolUse フックが失敗しなくなる
- [x] #2 CI ピン（Xcode 26.6）でもビルドが通り、CI が緑のままである
- [x] #3 CI ピンを 27.0 へ上げるか据え置くかを決め、決めた理由を Notes に残す
- [x] #4 swift test に残る失敗を特定し、この修正と無関係であることを示したうえで別タスクへ切り出す
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CI ランナーで Xcode 27 が使えるかを調べ、ピンを上げられるか確定する
2. nonisolated を外して @MainActor 隔離をクラスから継承させる
3. ローカルで swift build / swift test を回し、残る失敗がこの変更と無関係であることを示す
4. push して CI（26.6）でビルドが通ることを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## CI ピンの調査（実測 / 2026-09-16）

actions/runner-images の README を実物で確認した結果、**CI ピンは既に上限**だった。

- `macos-26` ランナーに入っている Xcode は 26.0.1 / 26.1.1 / 26.2 / 26.3 / 26.4.1 / 26.5 / 26.6 の 7 本で、**26.6 が最新かつ既定**。現在のピン（`ci.yml` × 2、`release.yml` × 1）がそのまま上限
- **`macos-27` ランナーは存在しない。** Xcode 27 はプレビュー扱いの `xcode-27` / `xcode-27-xlarge` ラベル（arm64）にしかない
- ローカルには Xcode 27.0（27A266a / Swift 6.4）しかなく、`xcode-select` で 26.6 へ戻せない

**決定（ユーザー判断）: CI ピンは 26.6 のまま据え置く。** GitHub が `macos-27` を正式提供するまで動かさない。プレビューイメージは予告なく変わる/消えるため、特に `release.yml`（署名・公証・配布物の生成）を載せる先としては採らない。ローカルへ Xcode 26.6 を併存させることもしない（AC #4 の切り分けどおり、両バージョンで通るコードにして CI を検知役にする）。

## 修正

`AppDelegate.main()` から `nonisolated` を外し、クラスと同じ `@MainActor` 隔離を継承させた（1 語の削除 + 経緯の doc コメント）。

`git log -L` で追ったところ、この `nonisolated` は初回コミット 074cb575 から付いており、コンパイラの指摘に応えて足されたものではなかった。`@MainActor` な `AppDelegate()` をこの関数の中で呼べている時点で実態はメインアクター上であり、宣言のほうが実態に合っていなかった。Swift 6.4 はそれを `main() must be @MainActor` で弾くようになっただけ。

## 検証

- ローカル（Xcode 27.0 / Swift 6.4）: `swift build` 成功。Swift ファイル編集時の PostToolUse フックも通るようになった
- `swift test --skip Integration --skip FileWatcherTests`: 1876 テスト中 10 issues。**失敗は PDFKit を実際に動かす 3 スイート・6 テストだけ**で、いずれも `AppDelegate` を参照しない。TASK-628 として切り出した
- swiftlint: 全体 46 件、`AppDelegate.swift` は 0 件（この変更で増えていない）
- CI（Xcode 26.6）での確認は push 後

## CI（Xcode 26.6）での確認

PR #674 の CI が全て pass（run 35042492395、2026-09-16）。

- `build-and-test`（macos-26 / Xcode 26.6）: pass / 7m20s ← **AC #2 はこれで判定**
- `changes`: pass / `js-test`: pass / `type-group-size`: pass / `thread-sanitizer`: skipping

`nonisolated` を外した形が Swift 6.1（Xcode 26.6）でも通ることを実測で確認した。
これでローカル（6.4）と CI（6.1）の両方でビルドが通る。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`AppDelegate.main()` から `nonisolated` を外し、クラスと同じ `@MainActor` 隔離を継承させた（1 語の削除）。Xcode 27.0 / Swift 6.4 で `main() must be '@MainActor'` となりローカルのビルドが落ち、Swift ファイルを編集するたび PostToolUse フックが失敗していた。

CI ピンは 26.6 のまま据え置いた。actions/runner-images の README を実物で確認したところ `macos-26` ランナーの Xcode は 26.6 が最新かつ既定で**ピンは既に上限**、`macos-27` ランナーは存在せず、Xcode 27 はプレビュー扱いの `xcode-27` ラベルにしかない（署名・公証を含む `release.yml` をプレビューイメージへ載せない判断）。

検証: ローカル（Xcode 27.0 / Swift 6.4）で `swift build` 成功、`swift test` は 1876 中 1870 成功。CI（macos-26 / Xcode 26.6）は PR #674 で `build-and-test` pass。残る 6 件は macOS 27 の PDFKit 挙動差で `AppDelegate` を参照せず、TASK-628 へ切り出した。
<!-- SECTION:FINAL_SUMMARY:END -->
