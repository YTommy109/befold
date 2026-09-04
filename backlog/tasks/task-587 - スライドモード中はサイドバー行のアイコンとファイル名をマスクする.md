---
id: TASK-587
title: スライドモード中はサイドバー行のアイコンとファイル名をマスクする
status: Done
assignee: []
created_date: '2026-09-04 14:19'
updated_date: '2026-09-04 14:40'
labels: []
dependencies: []
ordinal: 852000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-585 で入れたスライドモードは、行のアイコンとファイル名をそのまま出している。プレゼン中に映すものとしてはアイコンもファイル名も不要で、必要なのは「いまどれを選んでいるか」だけ。

行の中身を差し替える案（空ビュー＋固定高さ）も検討したが、行の高さを自前で導出し直す形になりフォントやメトリクスの変更で黙ってずれる。SwiftUI 標準の redacted によるマスクなら行の寸法をそのまま引き継げる。

FileListEntryRow の中でマスクしないこと。この型は FolderListingView（プレビュー内のフォルダー一覧）と共有していて、引数を通すとスライドモードと無関係な側にも配線が要る。マスクは呼び出し側（FileListView）でかける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 スライドモード中はサイドバー行のアイコンとファイル名が灰色の板に置き換わり、ファイル名が読めない
- [x] #2 選択行のハイライトは従来どおり見え、カーソルキーでの移動・クリック・ダブルクリック・コンテキストメニューが効く
- [x] #3 FileListEntryRow と FolderListingView は無改変で、プレビュー内のフォルダー一覧の見た目が変わらない
- [x] #4 スライドモードを解除すると行の見た目が元に戻る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

FileListView の FileListEntryRow へ .redacted(reason:) を 1 行付けた。マスクを行の中ではなく
呼び出し側でかけたのは、FileListEntryRow を FolderListingView と共有しており、引数を通すと
スライドモードと無関係な側にも配線が要るため。行を空ビューへ差し替える案は、行の高さを自前で
導出し直すことになりフォントやメトリクスの変更で黙ってずれるので採らなかった。

## 検証

- swift test: 1873 件すべて成功
- xcodebuild build -scheme befold: BUILD SUCCEEDED
- swiftlint: origin/main とのベースライン差分ゼロ
- scripts/check-type-group-size.sh --check: 閾値以内
- .redacted が Image(nsImage:)（NSWorkspace.shared.icon(forFile:) の実画像）にも効くことを実測。
  スライドモードに入れた状態で行を bitmapImageRepForCachingDisplay で描かせ、アイコンサイズの
  角丸の板が出ることを確認した（着手前は未確認の前提だった）。
  ファイル名側の板は幅 46pt に収まらず切り落とされる。
- 一覧全体の見え方は cacheDisplay では判定できない（SwiftUI 製の行が確実には描かれない）ため、
  アプリを起動してユーザーに目視で確認してもらった。

## 残っている検討事項

行がマスクされたことで「アイコン 16pt が切れない」という幅の根拠が弱くなった。ヘッダーの解除
アイコンが収まる幅（40pt 前後）まで詰められる可能性があるが、詰めると板も痩せてハイライトが
細くなるため、今回は 54pt のままにした。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
スライドモード中のサイドバー行に .redacted(reason: .placeholder) をかけ、アイコンとファイル名を灰色の板に置き換えた。マスクは呼び出し側（FileListView）でかけており、FolderListingView と共有している FileListEntryRow は無改変。行の寸法は redacted が引き継ぐので高さの決め打ちも無い。着手前に未確認だった「.redacted が NSWorkspace の実画像にも効くか」は実測で確認済み。swift test 1873 件成功、swiftlint ベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
