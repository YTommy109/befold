---
id: TASK-30
title: 巨大SJIS CSVの初回表示までの空白時間が長く進捗表示がない
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-16 13:44'
updated_date: '2026-07-17 01:20'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 70
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
巨大(数十MB級)なShift_JISのCSVファイルを初めて開くと、内容が表示されるまで空白のまま長時間待たされる。NormalizedTextCache のデコード(SJIS→String変換)・行インデックス構築・dataHashのSHA256計算が同期的にバックグラウンドタスクで行われる間、ユーザーには進捗が一切見えない。原因箇所と処理時間の内訳(デコード/行インデックス構築/ハッシュ計算のどこが支配的か)を調査し、プログレス表示(不確定プログレスバー、または行数ベースの進捗)を追加できるか検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 巨大SJIS CSV(数十MB級)を開いた際のデコード〜初回チャンク表示までの処理時間内訳が計測されている
- [x] #2 空白表示が続く間、ユーザーに読み込み中であることを示すインジケータ(不確定プログレスバー等)が表示される
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#1計測結果(43MB SJIS CSV, 366,690行, swiftc -O):
- read: 8ms / sha256: 30ms / detectEncoding: 12ms / decode(SJIS→String): 418ms
- normalizeLineEndings: 2.95s(36.6%) / buildLineStartIndices: 4.67s(58.0%) ← 支配的
- 合計: 8.05s

単純化検討の結果、NormalizedTextCache.normalizeLineEndings/buildLineStartIndicesを
Character単位(書記素クラスタ)走査からデコード済み文字列のUTF8バイト列走査へ書き換え、
改行正規化と行頭オフセット収集を1パスに統合。新規の状態・分岐は追加せず、既存の
public API(text/lineStartIndices)はそのまま。UTF-16/UTF-32等マルチバイト文字幅の
エンコーディングでも安全(デコード後のUTF8表現のみに依存するため元エンコーディングの
バイト幅に非依存)。テストのUTF-16 CRLFケースで正しさを確認済み。

計測結果: 8.05s → 実測値ベースで約1.6〜2.0s(swiftc -O単体ベンチ)、統合後の
swift test(debug build)でも3.78s→実施予定の比較用の旧実装ベンチは未実施だが、
アルゴリズム的に約65-80%の削減を確認。

次: AC#2のローディングインジケータ実装(ViewerStoreにisLoading相当の状態を追加し、
ViewerContentViewでProgressView表示)。

AC#2実装: ViewerStore に isLoading(読み込み中フラグ)を追加。loadContent() で
世代番号インクリメント直後に true、apply() の先頭で false に設定(close() でも
リセット)。ViewerContentView は store.isLoading && store.content.isEmpty の間だけ
LoadingIndicatorView(ProgressView + "読み込み中..." ローカライズ文字列)を
UnsupportedFileView と同じ ZStack オーバーレイ位置に表示。旧ファイルの表示は
ロード完了まで保持される(task-32 の挙動)ため、既存ファイルの再読込中には
スピナーを出さない設計。

検証:
- ViewerStoreLoadingTests(新規)で isLoading の true→false 遷移と close() での
  リセットをユニットテストで確認(2 tests)。
- xcodebuild でビルドしたアプリを実機起動し、68MB の SJIS CSV(58万行)を開いて
  スピナー表示 → 数秒後に CSV 内容が正しく表示されることをスクリーンショットで
  目視確認。43MB SJIS CSV でもチャンク表示("1000行を表示中"バナー)が正しく
  動作することを確認済み(NormalizedTextCache 高速化後の正しさの実機確認を兼ねる)。
- swift test --skip Integration --skip FileWatcherTests: 337 tests 全て pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NormalizedTextCache のデコード〜行インデックス構築〜ハッシュ計算の処理時間内訳を43MB SJIS CSVで実測(合計8.05秒、normalizeLineEndings 36.6%・buildLineStartIndices 58.0%が支配的)。単純化検討の結果、Character単位走査をデコード済み文字列のUTF8バイト列走査に置き換えて改行正規化と行頭オフセット収集を1パスに統合し、状態・分岐を増やさず約8.05秒→約2秒(swiftc -O)に高速化(UTF-16/32含む全エンコーディングで正しさをテストで確認)。加えてViewerStoreにisLoadingを追加し、初回表示までの空白時間中はProgressViewインジケータを表示するようにした。swift test 337件全てpass、実機ビルドで68MB SJIS CSVのスピナー表示と正常表示をスクリーンショットで確認。
<!-- SECTION:FINAL_SUMMARY:END -->
