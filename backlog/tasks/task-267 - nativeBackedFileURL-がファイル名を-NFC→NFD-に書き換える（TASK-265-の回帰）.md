---
id: TASK-267
title: nativeBackedFileURL がファイル名を NFC→NFD に書き換える（TASK-265 の回帰）
status: To Do
assignee: []
created_date: '2026-08-03 13:50'
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
- [ ] #1 NFC のバイト列を持つファイル名でも nativeBackedFileURL がバイト列を変えず、元の URL と == / hashValue が一致する
- [ ] #2 raw open() で作った NFC 名の fixture で上記を検証するテストがある（修正前の実装では落ちること確認済み）
- [ ] #3 native 裏打ちによる高速ハッシュの効果が維持されている（TASK-265 と同じ 344 件のベンチで比較値を Notes に残す）
- [ ] #4 非 file URL に対する契約が明示されている（precondition か早期 return）
- [ ] #5 テストは作成したファイルを名前で特定し、ディレクトリケースも covered。Foundation の実装詳細への hard assertion を外す
<!-- AC:END -->
