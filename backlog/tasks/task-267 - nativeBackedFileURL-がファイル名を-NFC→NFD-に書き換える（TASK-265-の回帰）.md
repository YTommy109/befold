---
id: TASK-267
title: nativeBackedFileURL がファイル名を NFC→NFD に書き換える（TASK-265 の回帰）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-03 13:50'
updated_date: '2026-08-03 14:24'
labels:
  - performance
  - bug
dependencies: []
priority: high
type: bug
ordinal: 458000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-265 で追加した URL.nativeBackedFileURL（BefoldApp/BefoldKit/URL+NormalizedPathKey.swift）が、URL(fileURLWithPath:) を経由するためパスをファイルシステム表現で再解釈し、**精密合成（NFC）の文字を NFD へ分解する**。修正前の `self.url = url` はディスク上のバイト列をそのまま保持していた。

## 実測（code-review high の verifier による）
raw open() で NFC のバイト列（`ペ-nfc.md` = U+30DA）を持つファイルを作ると、contentsOfDirectory は %E3%83%9A-nfc.md を返すが nativeBackedFileURL は %E3%83%98%E3%82%9A-nfc.md（U+30D8 U+309A）を返し、`n == u` が false、hashValue も異なる。

## 影響
APFS/HFS+ は照合が正規化非依存なので隠れるが、正規化に敏感なボリューム（ホーム配下にマウント/シンボリックリンクされた SMB・NFS・exFAT 共有）では顕在化する。Linux/Windows 側で NFC の名前（café.md, ダイアグラム.md）で作られた .md はサイドバーに出るのに、行を開くと存在しないパスを渡すことになり not found / 空プレビューになる。Copy Path / Copy File Reference（FileListView.swift:153,157）も解決できないパスを出す。

## 方針
パスを再解釈せずバイト列を保ったまま連続 UTF-8 化する実装に変える（URL(fileURLWithFileSystemRepresentation:) 経由など）。性能上の狙い（native 裏打ちによる高速ハッシュ）は維持したうえで、バイト列が変わらないことをテストで固定する。

## 併せて直すレビュー指摘（同じファイル・同じテスト）
- public API なのに非 file URL でも無条件に file URL として作り直し、scheme/query/fragment を捨てる（isFileURL の前提を明示するか早期 return）
- FileListEntryTests の fixture 名（日本語ファイル.md）は正規分解を持たないため、この書き換えを検出できない
- 同テストの `source.path.isContiguousUTF8 == false` は Foundation の実装詳細への hard assertion
- 同テストが listed.first を使っており、.DS_Store 等が混ざると別 URL を検証してしまう
- isDirectory: hasDirectoryPath のためのディレクトリケースが未テスト
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 NFC のバイト列を持つファイル名でも nativeBackedFileURL がバイト列を変えず、元の URL と == / hashValue が一致する
- [x] #2 raw open() で作った NFC 名の fixture で上記を検証するテストがある（修正前の実装では落ちること確認済み）
- [x] #3 native 裏打ちによる高速ハッシュの効果が維持されている（TASK-265 と同じ 344 件のベンチで比較値を Notes に残す）
- [x] #4 非 file URL に対する契約が明示されている（precondition か早期 return）
- [x] #5 テストは作成したファイルを名前で特定し、ディレクトリケースも covered。Foundation の実装詳細への hard assertion を外す
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-03）

URL(fileURLWithPath:) はパスを再解釈するため NFC を NFD へ分解する。ファイルシステム表現（ディスク上のバイト列）を通す実装に差し替えた。

```swift
guard isFileURL, !path.isContiguousUTF8 else { return self }
return withUnsafeFileSystemRepresentation { pointer in
    guard let pointer else { return self }
    return URL(fileURLWithFileSystemRepresentation: pointer, isDirectory: hasDirectoryPath, relativeTo: nil)
}
```

### 候補の比較（344 件・辞書挿入＋全件参照 1 パス／変換は 344 件ぶん）
| 実装 | ハッシュ | 変換コスト | バイト列 |
|---|---|---|---|
| 元の FileManager 由来 URL | 11.30 ms | — | 保たれる |
| URL(fileURLWithPath:)（回帰版） | 0.31 ms | — | **NFC→NFD に変化** |
| ファイルシステム表現（採用） | 0.31 ms | 0.70 ms | 保たれる |
| URL(string: absoluteString) | 0.30 ms | 2.94 ms | 保たれる |

性能は回帰版と同等のまま、バイト列が保たれる。URL(string:) より変換が 4 倍安いためこちらを採用。

### テスト
URLNativeBackedFileURLTests を新設。raw open(2) で NFC バイト列の fixture（ペ-nfc.md = U+30DA / café-nfc.md = U+00E9）を作り、== / hashValue / スカラー列 / 連続 UTF-8 を検証。**旧実装に戻して落ちることを確認済み**（ペ: U+30DA → U+30D8 U+309A、café: U+00E9 → U+0065 U+0301、hashValue も不一致）。ディレクトリケース（末尾区切りの保存）と、非 file URL（scheme/query/fragment を保つ）も追加。

FileListEntryTests 側は Foundation の実装詳細への hard assertion（source.path.isContiguousUTF8 == false）を外し、拡張子で対象ファイルを特定するようにした。

### 確認済み
- swift test 1008 tests / 151 suites green
- swiftlint ベースライン差分ゼロ（既存の identifier_name('id') のみ）
- xcodebuild build -scheme befold 成功
- GUI: backlog/ で tasks 行を 24 回往復する同一手順の sample で、メインスレッド 2632 中 idle 663・_normalizedHash 9 と TASK-265 修正直後（idle 614 / 8）と同等。バイト列保存版にしても性能は落ちていない
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
nativeBackedFileURL をファイルシステム表現経由の実装に差し替え、NFC のファイル名を NFD へ書き換える回帰を解消した。性能は回帰版と同等（344 件で 11.30ms → 0.31ms、変換 0.70ms）。raw open(2) で NFC バイト列の fixture を作る回帰テストを新設し、旧実装で落ちることを確認済み。非 file URL は自身を返す契約を明示し、ディレクトリケースも covered。swift test 1008 green / swiftlint ベースライン差分ゼロ / xcodebuild 成功 / GUI sample も TASK-265 修正直後と同等。
<!-- SECTION:FINAL_SUMMARY:END -->
