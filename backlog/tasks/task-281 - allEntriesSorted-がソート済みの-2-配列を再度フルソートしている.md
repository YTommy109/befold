---
id: TASK-281
title: allEntriesSorted がソート済みの 2 配列を再度フルソートしている
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 02:01'
updated_date: '2026-08-04 05:29'
labels:
  - review-finding
dependencies: []
priority: low
type: chore
ordinal: 471000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DirectoryLister.allEntriesSorted（DirectoryLister.swift:84）は (folders + files) に対して sortedByFileName() をかけ直しているが、DirectoryEnumeration.sortedContents は既に同じ比較子（lastPathComponent の localizedStandardCompare）で各半分をソート済みで返している。ロケール依存の重い比較子で O(n log n) を丸ごと払い直しており、しかも TASK-273 でこの行には要素ごとの nativeBackedFileURL 再構築も乗った。Quick Open の候補列挙経路にあたる。

ソート済み 2 配列の線形マージ、または未ソートの結合に対して 1 回だけソートすれば、同じ結果を O(n) 回の比較で得られる。指摘自体は TASK-273 以前からある既存の無駄だが、当該行が今回の差分で変更されているためここで直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 大きなフォルダーで allEntriesSorted の比較回数が減っている（マージまたは単一ソートに置き換わっている）
- [x] #2 フォルダー先頭・ファイル後続の並び順と、ファイル名比較の順序が従来と一致することをテストで確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ソート済み 2 列をマージするヘルパーを、列挙の並びを決める場所(BefoldKit の sortedByFileName の隣)に置く。比較のキーはクロージャで受け、URL と FileListEntry の双方から使えるようにする。
2. allEntriesSorted の (folders + files).sortedByFileName() をマージに置き換える。
3. 同じ重複が buildEntries の .alphabetical にもある(比較子を手書きで再実装していた)ので、同じヘルパーに寄せる。
4. マージの並びが連結して全ソートした場合と一致することをテストで固定する(数字・大文字小文字・非 ASCII を混ぜる)。片側が空の場合も見る。
5. 比較を壊すとテストが落ちること、および実際に速くなっていることを実測する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 同じ重複がもう 1 箇所あったので、まとめて寄せた

指摘は allEntriesSorted(DirectoryLister.swift:84)だけだったが、buildEntries の .alphabetical にも同じ形の無駄があった(ソート済みの folderEntries と fileEntries を連結して sorted し直す)。しかもそちらは localizedStandardCompare の比較子を sortedByFileName とは別に手書きしており、並び順の定義が 2 箇所に散っていた。マージのヘルパーを 1 つ作って両方をそこへ寄せ、比較子の重複も消した。

ヘルパーは比較キーをクロージャで受ける形にして、URL(lastPathComponent)と FileListEntry(url.lastPathComponent)の双方から使えるようにしている。同順(orderedSame)のときは左を先に出し、連結の前後関係を保つ。

## 実測

- 20,000 件(フォルダー 10,000 + ファイル 10,000、非 ASCII 名)で 5 回平均: マージ 18.4ms / 連結して全ソート 44.3ms。約 2.4 倍速く、1 回あたり約 26ms を削っている。
- マージの比較を壊す(常に左を採る)と、追加した並び順一致テストが落ちることを実測。なお既存の allEntriesSortedOrdersNaturallyIncludingHidden は Set と 1 組の相対順序しか見ておらず、壊しても通ってしまう。今回のテストがその穴を埋めている。

## 検証

- swift test: 971 tests / 138 suites 成功。xcodebuild build -scheme befold: BUILD SUCCEEDED。
- swiftlint: origin/main と比較して新規警告ゼロ(差分は TASK-279 で増えた ViewerStore.swift の行数のみ)。swiftformat: 差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ソート済み 2 列のマージヘルパーを列挙側に用意し、allEntriesSorted の再ソートと、同じ重複があった buildEntries の .alphabetical(比較子を手書きで再実装していた)を両方そこへ寄せた。20,000 件で 44.3ms → 18.4ms(約 2.4 倍)を実測。並び順が連結して全ソートした場合と一致することをテストで固定し、比較を壊すと落ちることも実測した。検証: swift test 971 件成功、xcodebuild BUILD SUCCEEDED、swiftlint は main 比で新規警告ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
