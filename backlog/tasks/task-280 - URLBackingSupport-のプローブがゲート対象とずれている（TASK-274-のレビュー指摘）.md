---
id: TASK-280
title: URLBackingSupport のプローブがゲート対象とずれている（TASK-274 のレビュー指摘）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 02:01'
updated_date: '2026-08-04 02:59'
labels:
  - review-finding
dependencies: []
priority: medium
type: bug
ordinal: 470000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-274 で環境依存のテスト失敗をなくすため URLBackingSupport.rebuildYieldsContiguousUTF8 を導入し、isContiguousUTF8 のアサートをその判定でゲートした。だがプローブが測っているものとゲート先が測っているものが揃っておらず、環境依存を別の形で残している。実測点は macOS 14 と 26 の 2 点のみ。

1. ゲートとアサートの API 不一致: プローブは URL(fileURLWithFileSystemRepresentation:) の再構築が contiguous UTF-8 を返すかだけを測る。一方 FileListEntryTests.swift:39 のアサート対象 entry.pathKey は resolvingSymlinksInPath().path 由来で、プローブが一切測っていない別 API。再構築は contiguous だが resolvingSymlinksInPath は NSString ブリッジのまま、という OS があると、URLNativeBackedFileURLTests 側は通るのに FileListEntryTests だけ落ちる。
2. 無記録のスキップ: URLNativeBackedFileURLTests.swift:45 ほかで、以前は無条件だった 4 つの isContiguousUTF8 アサートが plain な `if` で囲われた（withKnownIssue でも記録付き skip でもない）。プローブが false の環境ではテストレポートに何の痕跡も残さず消える。プローブは「この OS では再構築が no-op」と「この OS では害がない」を同一視しているが、再構築が効かないのに遅いブリッジ経路は残る OS があり得る。その場合、性能回帰が無検知で出荷される。
3. 環境障害がバッキング回帰に見える: probe() は TempDir 作成・ファイル作成・列挙のいずれが失敗しても true を返す（URLBackingSupport.swift:22）。macOS 14 の一時ファイルシステムの一過性の不調で 4 つのアサートが全部落ち、失敗メッセージは nativeBackedFileURL を指すためプローブ I/O が原因だと分からない。fail-loud 自体は意図どおりでも、プローブ不確定という状態が見えるようにすべき。
4. 本番 API の再実装: probe() は withUnsafeFileSystemRepresentation + URL(fileURLWithFileSystemRepresentation:) を手書きし、ゲート対象の URL.nativeBackedFileURL 自体を呼んでいない。しかも既に乖離している（本番は isDirectory: hasDirectoryPath、プローブは isDirectory: false）。BefoldTestSupport に BefoldKit 依存を足し（Package.swift に現状なし）、source.nativeBackedFileURL.path.isContiguousUTF8 でゲートすれば乖離しようがなくなる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ゲート条件が、そのゲートで守られるアサートと同じ API のバッキングを測っている（pathKey 側は pathKey の生成 API で判定する）
- [x] #2 プローブが false でアサートを実行しない場合、テストレポートにスキップまたは既知の問題として記録が残る
- [x] #3 プローブが環境障害で判定できなかった場合、バッキング回帰と区別できる形で報告される
- [ ] #4 プローブが本番の URL.nativeBackedFileURL を直接呼び、実装をコピーしていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. プローブを「Foundation の振る舞いを直接測る」ものとして残し、本番 API(nativeBackedFileURL)は呼ばない。呼ぶと本番が壊れたとき観測値も一緒に動き、アサートが素通りする。
2. 作り直しの引数を本番と揃える(isDirectory: hasDirectoryPath)。乖離の原因を潰す。
3. 観測を 2 つに分ける: 作り直し後のパス(nativeBackedFileURL 用)と、そこから resolvingSymlinksInPath したパス(pathKey 用)。ゲートとアサートの API 不一致を解消する。
4. 観測できなかった場合は Bool を返さずエラー(ProbeFailed)にし、テスト側の try で「プローブが測れなかった」と名指しで落ちるようにする。
5. テスト側は if によるスキップをやめ、「実測値と一致するか」の等値アサートにする。常に実行されるので黙って消えることがなく、逆方向(揃わない環境なのに揃った)も捕まえる。
6. 本番 API を no-op に壊してアサートが落ちることを実測で確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## レビュー指摘のうち 1 点は、指摘どおりに直すと逆効果だった

指摘 4 は「プローブが本番の URL.nativeBackedFileURL を呼ばずに実装をコピーしている。BefoldTestSupport に BefoldKit 依存を足して本番 API でゲートせよ」だった。いったんそのとおり実装したが、これは**アサートを空振りさせる**。ゲートとアサートが同じ API を呼ぶため、本番が裏打ちを差し替えなくなると観測値も false に動き、「差し替わらない環境だ」と観測して等値が成立してしまう。裏打ちの回帰が無検知で通る。

そのため、プローブは Foundation の振る舞いを直接測るものとして残した。指摘が本当に問題にしていた乖離(本番は isDirectory: hasDirectoryPath、プローブは false)は引数を揃えて潰した。この判断により BefoldTestSupport → BefoldKit の依存も不要になり、Package.swift に明記された「BefoldTestSupport は BefoldKit へ依存しない」制約も守れている。

## 直した内容

- 観測を 2 つに分けた: rebuiltPathIsContiguousUTF8(nativeBackedFileURL 用)と resolvedPathIsContiguousUTF8(pathKey = normalizedPathKey 用)。pathKey は resolvingSymlinksInPath を通る別 API なので、同じ値になる保証がない。
- 観測できない場合は Bool ではなくエラー(ProbeFailed)を返す。テスト側の try で「プローブ自身が動かせなかった」と名指しで落ちる。以前は true を返しており、一時ファイルシステムの不調が裏打ちの回帰に見えていた。
- テスト側の if によるスキップを廃止し、「実測値と一致するか」の等値アサートにした。アサートが黙って消えることがなくなり、「揃わない環境なのに揃った」という逆方向の変化も捕まえる。

## 検証

- 本番の nativeBackedFileURL を no-op に壊すと、両テストファイル計 5 件のアサートが落ちることを実測（pathKey 側も含む）。アサートに歯があることの裏付け。壊した変更は元に戻し済み。
- この環境(macOS 26.6)の観測値は rebuilt=true / resolved=true。従来の判定と同じ向き。
- swift test: 967 tests / 137 suites 成功。xcodebuild build -scheme befold: BUILD SUCCEEDED。
- swiftlint: 触れた 3 ファイルの警告 0 件。swiftformat: fix モード適用後 lint 差分なし。
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-08-04 02:59
---
受け入れ条件 4「プローブが本番の URL.nativeBackedFileURL を直接呼び、実装をコピーしていない」は満たしていない。実装してみた結果、満たすとアサートが空振りすることが分かったため（Notes 参照）。判断に異議があれば戻せる。
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
プローブとアサートのずれを、観測を API ごとに分けることと、スキップをやめて等値アサートにすることで解消した。観測は rebuiltPathIsContiguousUTF8(nativeBackedFileURL 用)と resolvedPathIsContiguousUTF8(pathKey 用)の 2 つになり、テストはどちらも実測値と一致するかを常に検証する。観測できなかった場合は Bool ではなく ProbeFailed を返し、プローブの失敗が裏打ちの回帰に見えないようにした。指摘 4(本番 API でゲートせよ)は、そのとおりに直すとゲートとアサートが同じ API を呼んでアサートが空振りするため採用せず、乖離の実害だった引数の不一致(isDirectory)を揃える形にした。検証: 本番 API を no-op に壊すと 5 件のアサートが落ちることを実測、swift test 967 件成功、xcodebuild BUILD SUCCEEDED。
<!-- SECTION:FINAL_SUMMARY:END -->
