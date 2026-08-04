---
id: TASK-269
title: macOS 14 では nativeBackedFileURL が no-op になる可能性を検証する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-03 13:51'
updated_date: '2026-08-03 14:33'
labels:
  - performance
dependencies: []
priority: medium
ordinal: 460000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review high の PLAUSIBLE 指摘。Package.swift は .macOS(.v14)、project.yml も macOS 14.0 を宣言しているが、.github/workflows/ci.yml のテストは macos-26 でしか走らない。

nativeBackedFileURL は URL(fileURLWithPath:) が Swift native の文字列ストレージを保持することを前提にしているが、NSURL/CFURL 裏打ちの URL 実装ではそうならない。verifier が当該実装を強制して確認したところ、連続 UTF-8 の Swift 文字列を渡しても `URL(fileURLWithPath: s).path.isContiguousUTF8 == true` に対し `(NSURL(fileURLWithPath: s) as URL).path.isContiguousUTF8 == false` だった。

これが macOS 14 の実 Foundation にも当てはまるなら、macOS 14 のユーザーには TASK-265 のフリーズが残ったまま、エントリごとのパスコピーと URL 再構築のコストだけが増えることになる。FileListEntryTests の isContiguousUTF8 アサートは macos-26 でしか走らないため、CI では検出できない。

まず macOS 14 実機（または該当 SDK）で成立するかを確認し、成立するなら nativeBackedFileURL 側で裏打ちを保証できる実装に直すか、macOS 14 のサポート方針そのものを判断する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 macOS 14 の Foundation で nativeBackedFileURL が期待どおり native 裏打ちの URL を返すかどうかを実測で確認する
- [x] #2 no-op になる場合、実装の修正かサポート方針の判断（どちらを採るか）を Notes に記録する
- [x] #3 CI が deployment target を検証しない件について、対処するか許容するかを明記する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実測結果（2026-08-03・GitHub Actions ランナーで採取）

macOS 14 実機がないため、一時ブランチ ci/macos14-url-probe に単体プローブ（本体と同じ実装を複製した .swift）を置き、macos-14 / macos-26 の 2 ランナーで走らせた。日本語名 344 件を FileManager で列挙し、URL を辞書キーにする 1 パス（挿入＋全件参照）の最良値。

| ランナー | OS / Swift | 元の URL | 作り直した URL | 裏打ち | 判定 |
|---|---|---|---|---|---|
| macos-14 | 14.8.7 / Swift 5.10 | 0.334 ms | 0.327 ms | 揃わない | **NO-OP** |
| macos-26 | 26.5.2 / Swift 6.3.3 | 0.453 ms | 0.175 ms | 揃う | EFFECTIVE |
| 手元 | 26.6 | 11.633 ms | 0.179 ms | 揃う | EFFECTIVE |

### 結論: 指摘は「no-op」の部分は正しいが、「macOS 14 のユーザーにフリーズが残る」は誤り

macOS 14 では URL の実装が異なるため作り直しても裏打ちは揃わず、nativeBackedFileURL は実質 no-op。**ただし macOS 14 では遅い経路自体が存在しない**（元の URL のハッシュが 0.334 ms＝macOS 26 で修正した後と同水準。手元の macOS 26.6 の 11.6 ms と比べて 35 倍速い）。TASK-265 のフリーズは macOS 15 以降の URL 実装に由来するものであり、macOS 14 のユーザーは元から影響を受けない。

したがって実装の分岐は不要。macOS 14 で残るのは「エントリごとに変換を試みて外す」ぶんのコストだけで、344 件で 0.7 ms（同じ一覧のディレクトリ列挙 12 ms に対して無視できる）。この事実を URL+NormalizedPathKey.swift の doc コメントに残した。

### CI が deployment target を検証しない件
macos-14 ランナーには Xcode 16.2（Swift 6）が入っており、setup-xcode で指定すれば本体（swift-tools-version: 6.0）のビルド・テストを macOS 14 上で回すこと自体は可能。ただし CI の Xcode が 26.5 と 16.2 に分岐し、ツールチェーン差分に起因する赤を別途面倒見ることになる。本件の疑問（no-op か否か）は上記プローブで決着したため、**常設ジョブは追加しない**判断とした。macOS 14 実行時の API 可用性まで CI で担保したくなった時点で、改めて matrix ジョブとして起票する。

プローブ用のブランチ・ワークフロー・スクリプトは計測後に削除済み（リポジトリには残していない）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
macos-14 / macos-26 の CI ランナーでプローブを実測し、nativeBackedFileURL は macOS 14 では no-op だが、macOS 14 には遅い経路自体が存在しない（344 件のハッシュが 0.334ms で、macOS 26 の修正後と同水準）ことを確認した。macOS 14 のユーザーにフリーズは残らないため実装の分岐は不要と判断し、事実を doc コメントに記録。CI への常設 macos-14 ジョブは追加しない（Xcode 16.2 で可能だがツールチェーン分岐のコストに見合わない）。プローブ資材は削除済み、swift test 1008 green。
<!-- SECTION:FINAL_SUMMARY:END -->
