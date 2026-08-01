---
id: TASK-241
title: GitCommandFileIndex のロック保持中に git subprocess を待たないようにする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-01 10:39'
updated_date: '2026-08-01 10:56'
labels:
  - refactor
  - performance
dependencies: []
priority: high
type: task
ordinal: 444000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitCommandFileIndex (befold/App/GitCommandFileIndex.swift) は NSLock を 1 本だけ持ち、取得箇所は repositoryRoot(forFileAt:) (L46) と trackedFileIndex(forFileAt:) (L51) の 2 箇所。どちらもロックを保持したまま GitRepository 経由で git subprocess を同期待ちする (L58/L63/L91)。GitCommandRunner の timeout 10 秒 + terminationGrace 5 秒がまるごとロック内に入るため、あるリポジトリで git が遅いと別リポジトリのウィンドウまで最大 15 秒巻き添えでブロックされる (クラス冒頭コメント L10-19 が自認)。

キャッシュ参照と subprocess 実行を分離し、ロックはキャッシュの読み書きだけを守る形にする (root ごとの in-flight 管理などで同一 root の重複実行は抑止しつつ、異なる root は互いに待たない)。async 化は不要で、GitFileIndexing / GitRepositoryReading のシグネチャは同期のまま維持する。

TASK-226 (Runner の async 化) から実害の大きい部分だけを切り出したタスク。226 は予防的懸念として保留中だが、本タスクは波及がなく単独で着地できる。TASK-186 系 (サイドバー Git ステータス) が同じ索引の上に載るため先に効く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 異なるリポジトリに対する repositoryRoot / trackedFileIndex 呼び出しが互いにブロックしない
- [x] #2 同一 root への同時呼び出しで git subprocess が重複実行されない
- [x] #3 既存のキャッシュ・LRU (maxCachedRoots=4)・fingerprint 無効化の挙動が維持され GitCommandFileIndexTests が通る
- [x] #4 GitFileIndexing / GitRepositoryReading のシグネチャが同期のまま変更されていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitCommandFileIndex.swift に KeyedLock(キーごとに相互排他を与える小さなヘルパー。registryLock で NSLock を refcount 管理し、waiters が 0 になったら登録を削除)を追加する
2. 単一 NSLock を 3 つに分ける: stateLock(rootByDir / entryByRoot / rootsByRecency の読み書きのみを保護)、dirLocks(ディレクトリキーごと)、rootLocks(ルートキーごと)
3. resolvedRoot: stateLock でキャッシュ参照 → 未命中なら dirLocks.withLock(dirKey) で二重チェック → repository.root(forFileAt:) を stateLock 非保持で実行 → 確定時のみ stateLock で保存
4. trackedFileIndex: resolvedRoot でルート解決(dir ロックは解放済み)→ rootLocks.withLock(rootKey) 内で indexFingerprint / trackedFiles / SuffixPathIndex 構築を stateLock 非保持で実行 → 結果の書き込みだけ stateLock。同一 root への同時呼び出しは rootLocks で直列化されるため 2 人目はキャッシュ命中し subprocess が重複しない
5. デッドロック回避: dirKey と rootKey は値が一致しうる(ルート直下のファイル)ため registry を 2 本に分け、かつ dir ロックは root ロック取得前に必ず解放する(ネストしない)
6. クラス冒頭の doc コメントと warm の 'in-flight 管理を足すほどの重複コストにならない' コメントを新しい構造に合わせて書き直す
7. テストを先に追加する(TDD): (a) 遅い root の列挙中に別リポジトリの呼び出しが完了する (b) 同一 root への同時呼び出しで trackedFiles が 1 回しか呼ばれない。既存 13 テストが無改変で通ることも回帰条件
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 単一 NSLock を 3 つに分割した。stateLock はキャッシュ辞書(rootByDir / entryByRoot / rootsByRecency)の読み書きだけを守り、git subprocess を待つ間は握らない。dirLocks / rootLocks は新設の KeyedLock(キーごとに NSLock を refcount 管理し、待ち人数が 0 になったら登録から削除)で、ディレクトリキー / ルートキーごとに相互排他を与える。

resolvedRoot はキャッシュ参照 → 未命中なら dirLocks 内で二重チェック → repository.root を stateLock 非保持で実行 → 確定時のみ stateLock で保存、の順。trackedFileIndex は resolvedRoot(dir ロックは解放済み)でルートを得てから rootLocks 内で indexFingerprint / trackedFiles / SuffixPathIndex 構築を行い、書き込みだけ stateLock を取る。

デッドロック回避: ルート直下のファイルでは dirKey と rootKey が同じ値になりうるため registry を 2 本に分け、かつ dir ロックを root ロック取得前に必ず解放してネストさせない。KeyedLock は registryLock を手放してから対象ロックを待つ(握ったまま待つとキーを分けた意味が消える)。

テストは TDD で先に追加。GitCommandFileIndexTests.swift が SwiftLint の file_length(400 行)を超えたため、並行性の 2 テストとそのフェイク(BlockingRepository / SlowRepository)を GitCommandFileIndexConcurrencyTests.swift へ分離した。

検証: 追加前に「遅いリポジトリの列挙中でも別リポジトリの解決は完了する」が waitUntil 10 秒タイムアウトで red になることを確認済み(実装後は green)。swift test --skip Integration --skip FileWatcherTests で 950 テスト / 122 スイート全て成功。swift test --sanitize=thread --filter GitCommandFileIndexTests で 14 テスト成功・データ競合の検出なし。swiftformat --lint はエラー 0、swiftlint は違反 74 → 73 件(本変更で新規違反なし)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitCommandFileIndex の単一 NSLock を、キャッシュ辞書だけを守る stateLock と、キーごとに相互排他を与える KeyedLock 2 本(dirLocks / rootLocks)に分割した。git subprocess(rev-parse / ls-files / index fingerprint)と SuffixPathIndex の構築は stateLock を保持せずに実行するため、あるリポジトリで git が遅くても別リポジトリのウィンドウは待たされない(従来は最大 15 秒 = timeout 10s + grace 5s 巻き添えだった)。同一ルートへの同時呼び出しは rootLocks が直列化し、待った側はキャッシュ命中するため列挙は 1 度しか走らない。GitFileIndexing / GitRepositoryReading のシグネチャは同期のまま無変更で、波及は GitCommandFileIndex.swift 1 ファイルに収まっている。検証: 実装前に別リポジトリ非ブロックのテストが red になることを確認した上で、swift test 950 テスト全成功、ThreadSanitizer で当該 14 テスト成功・競合検出なし、swiftformat/swiftlint に新規違反なし。
<!-- SECTION:FINAL_SUMMARY:END -->
