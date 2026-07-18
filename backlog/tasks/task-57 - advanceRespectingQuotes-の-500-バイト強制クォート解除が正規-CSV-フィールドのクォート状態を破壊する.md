---
id: TASK-57
title: advanceRespectingQuotes の 500 バイト強制クォート解除が正規 CSV フィールドのクォート状態を破壊する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-18 08:13'
updated_date: '2026-07-18 08:48'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-53 の修正で導入した quotedRunLength ≥ 500 での inQuotes 強制リセットに3つの正確性バグがある:
(1) 正規の 500 バイト超クォートフィールドで強制リセット後、本来の閉じクォートが inQuotes を true に戻し、以降全フィールドのクォート状態が反転する。
(2) maxChunkBytes 境界での snappedToCharacterBoundary バックアップにより、マルチバイト文字の継続バイトが quotedRunLength に二重カウントされ、~499-500 バイトの正規フィールドで誤った強制解除が発動する。
(3) inQuotes=true 中に消費された行は linesConsumed にカウントされないため、不平衡クォート後のチャンクが linesPerChunk を超過する。
コードレビュー（arch-saguaro ブランチ、2026-07-18）で発見。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 500 バイト超の正規クォートフィールドを含む CSV で、後続フィールドのクォート状態が正しく追跡される
- [x] #2 マルチバイト文字を含むクォートフィールドが maxChunkBytes 境界をまたいでも quotedRunLength が正確にカウントされる
- [x] #3 不平衡クォート後の強制解除を経たチャンクの行数が linesPerChunk を大幅に超過しない
- [x] #4 各シナリオに対応するユニットテストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. inQuotes を強制的に false へ書き換える500バイト不均衡判定を廃止し、代わりに
   hasGivenUpQuoteTracking フラグを新設する。実際のクォート対応(inQuotes)は
   常にtoggleのみで管理し、本物の閉じクォートが来れば正しく復元される
   (バグ1: 正規500バイト超フィールドでのクォート状態破壊を修正)。
2. 行末カウント条件を `!inQuotes` から `!inQuotes || hasGivenUpQuoteTracking` に変更し、
   不均衡とみなした後は行ベース分割を再開できるようにする
   (バグ3: 不平衡クォート後のチャンク行数超過を緩和)。
3. maxChunkBytes 境界での強制分割時、snappedToCharacterBoundary が巻き戻した
   マルチバイト継続バイト分だけ quotedRunLength を差し引き、二重カウントによる
   誤った不均衡判定を防ぐ(バグ2)。
4. 各バグを再現する回帰テストを追加し、fix適用前後でテストが実際に
   fail/passすることを手動で検証する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
hasGivenUpQuoteTracking を新設し、500バイト超過時も inQuotes 自体は書き換えず toggle のみで管理する設計に変更。maxChunkBytes境界での強制分割時はquotedRunLengthのロールバックを追加。3つの回帰テストを追加し、それぞれ修正前のコードに戻して実際にfailすることを確認済み(longLegitimateQuotedFieldDoesNotCorruptSubsequentQuoteState, multibyteCharacterAtChunkBoundaryInsideQuotedFieldIsNotDoubleCounted)。既存のunbalancedQuoteGivesUpAfterGuaranteedLengthAndRecoversに上限アサーション(chunks.count<=6)を追加してAC#3を検証。swift test 全354件成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
advanceRespectingQuotesの500バイト不均衡判定を、inQuotesを直接書き換える方式からhasGivenUpQuoteTrackingという独立フラグに変更した。inQuotesは常にtoggleのみで管理されるため、本物の閉じクォートが後で見つかっても状態が反転しない(バグ1修正)。行カウント条件をhasGivenUpQuoteTrackingも許可するよう変更し不均衡後の行ベース分割再開を維持しつつ(バグ3)、maxChunkBytes境界でのマルチバイト巻き戻し時にquotedRunLengthも同期して差し引くことで二重カウントを防いだ(バグ2)。StringChunkReaderTests.swiftに3件のテストを追加(1件は既存テストの強化)。各新規テストは修正前のコードでは実際にfailすることを手動で確認済み。swift build / swift test(354件)は全て成功。
<!-- SECTION:FINAL_SUMMARY:END -->
