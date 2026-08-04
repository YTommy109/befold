---
id: TASK-280
title: URLBackingSupport のプローブがゲート対象とずれている（TASK-274 のレビュー指摘）
status: To Do
assignee: []
created_date: '2026-08-04 02:01'
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
- [ ] #1 ゲート条件が、そのゲートで守られるアサートと同じ API のバッキングを測っている（pathKey 側は pathKey の生成 API で判定する）
- [ ] #2 プローブが false でアサートを実行しない場合、テストレポートにスキップまたは既知の問題として記録が残る
- [ ] #3 プローブが環境障害で判定できなかった場合、バッキング回帰と区別できる形で報告される
- [ ] #4 プローブが本番の URL.nativeBackedFileURL を直接呼び、実装をコピーしていない
<!-- AC:END -->
