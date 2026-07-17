---
id: TASK-41
title: サイズ超過テキストが「未対応フォーマット」と誤表示される(サイズ上限チェックが3箇所に重複)
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-17 02:07'
updated_date: '2026-07-17 08:17'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 3100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.computeLoad の事前サイズチェックは `if let size = fileReader.fileSize(at:)` で、fileSize が nil を返すと黙ってスキップされる(DefaultFileReader は resourceValues 失敗で nil を返し得る。サイズチェック後に readData までにファイルが100MBを超える TOCTOU もある)。その場合 NormalizedTextCache.init が NormalizedTextCacheError.fileTooLarge を throw するが、computeLoad の generic catch が全エラーを .unsupportedFormat にマップするため、ユーザーには「未対応フォーマット」と誤った理由が表示される。

背景: 100MB 上限の強制が ContentLoader.swift:33、computeLoad(:291-296, :310-315)、NormalizedTextCache.init の3箇所に重複しており、理由マッピングが揃っていない。修正時は単純化(上限チェックの単一情報源化、例: テキスト読み込み分岐を ContentLoader へ戻す)を先に検討する。TASK-2(エンコーディング検出の単一情報源化)と関連。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 NormalizedTextCacheError.fileTooLarge が rejectReason .fileTooLarge として表示される(テストあり)
- [x] #2 サイズ上限の判定と理由マッピングの単一情報源化を検討し、結果をタスクに記録する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. computeLoad の catch ブロックで NormalizedTextCacheError を .fileTooLarge にマップする(TOCTOU/fileSize nil 時の誤表示を修正)。2. 単純化の検討結果をタスクに記録する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 単純化の検討(AC#2)

3箇所のサイズ上限チェックは以下のように対象・上限値が異なり、単一のチェック関数へ統合すると
fileType 分岐や2種類の上限値(バイナリ50MB/非行指向テキスト10MB/行指向100MB)を引数化する
ラッパーが必要になり、むしろ複雑化する。実質的な重複は「fileReader.fileSize(at:) > limit」
という1行のみで、抽出するほどの重複ではないと判断した。

- ContentLoader.load: バイナリ 50MB 上限(事前チェックのみ、読み込み前に弾く)
- computeLoad 事前チェック: fileType に応じた上限(行指向100MB/非行指向10MB)。fileSize が
  取得できる場合の高速な事前弾き
- NormalizedTextCache.init: 常に100MBのハードキャップ(事前チェックが nil を返した場合や
  TOCTOU で肥大化した場合の安全網)
- computeLoad 事後チェック(非行指向のみ): デコード後のテキストサイズを10MB上限で再チェック
  (デコードでバイト数が変化しうるため)

真のバグは上限値の重複ではなく、NormalizedTextCache.init が投げた fileTooLarge を
computeLoad の catch が汎用 unsupportedFormat に丸めていたことだった。ここを
NormalizedTextCacheError を明示的に判別してマップするよう修正し、単一のエラー理由の
情報源(スロー元の Error 型)を正しく伝播させることで対応した。3箇所の上限値自体は
対象ごとに異なる制約のため統合しない。TASK-2 とは無関係な独立事象と確認。

## 実装
- ViewerStore.computeLoad の catch で error is NormalizedTextCacheError を判定し
  .fileTooLarge を返すよう修正
- ViewerStoreTests に TOCTOU(fileSize nil + 実データ100MB超)で fileTooLarge が
  維持されることを確認するテストを追加
- swift test: 365 tests 全て pass
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
computeLoad の catch ブロックで NormalizedTextCacheError を明示的に判別し .fileTooLarge を返すよう修正(以前は unsupportedFormat に丸められていた)。単純化(上限チェックの単一情報源化)を検討したが、3箇所は対象ごとに異なる上限値(バイナリ50MB/非行指向テキスト10MB/行指向100MB)を扱う独立した制約であり統合は複雑化を招くと判断、代わりにエラー理由の伝播経路を修正した(検討結果はノートに記録)。ViewerStoreTests に TOCTOU(fileSize が nil を返し実データが100MB超)シナリオのテストを追加。swift build / swift test で 365 tests 全て pass を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
