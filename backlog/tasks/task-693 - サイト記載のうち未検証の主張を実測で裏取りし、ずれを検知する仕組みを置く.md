---
id: TASK-693
title: サイト記載のうち未検証の主張を実測で裏取りし、ずれを検知する仕組みを置く
status: Done
assignee:
  - '@claude'
created_date: '2026-10-09 07:33'
updated_date: '2026-10-09 07:56'
labels: []
milestone: m-12
dependencies: []
priority: low
type: task
ordinal: 882000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
調査（2026-10-09）はコード読みだけで、次は未検証: ライブリロード 0.2 秒、通信はアップデート確認のみ、HTML 内スクリプトは実行しない、git を知っているリンク解決と worktree 追従、Quick Open の空欄時の最近/ブックマーク表示、「さらに読み込む」の文言、サイドバーバッジの色分け。site 側の既存テスト（test/shortcuts.test.ts・test/file-types.test.ts）は npx vitest が止まり、実行できていない。記事 Markdown は ja/en のサイズ差が約 1.4 倍（ai-code-review は 3.5K と 2.5K）で、段落対応は未検証。今回の食い違いは、今のところ人が読み比べないと見つからない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 上記の未検証の主張それぞれについて、実測またはコード参照で 一致／食い違い を Notes に記録している
- [x] #2 site の vitest が止まる原因を特定し、test/shortcuts.test.ts と test/file-types.test.ts の合否を実測で示している
- [x] #3 記事 Markdown の ja/en で段落が対応しているかを確認し、ずれがあれば直している
- [x] #4 サイトの SHORTCUTS が実装のメニュー定義とずれたら落ちるテスト、またはそれが成立しない理由と代替の運用を残している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-692 での発見（2026-10-09）: (1) この worktree は site/node_modules が無く、npm ci（5 秒）後は vitest が通る。止まった原因の第一候補。(2) test/shortcuts.test.ts は「表 ⊆ 実装」の片方向だけを見ており、実装にあって表に無いショートカット（⇧⌘P・⌘←/→ が実例）は検知できない。AC 4 の対象はこの穴。除外する標準操作（⌘, など）の一覧を明示する形が候補。

AC1 裏取り結果（2026-10-09、コード読み。アプリの実行・実通信の観測はしていない）
一致: (2) 通信はアップデート確認だけ — Swift 側に URLSession 等 0 件、依存は Sparkle のみ、viewer.html は connect-src none。ただし更新確認の宛先は配布サイトの Worker で、サイト側が計測している（サイトの文言と矛盾はしないが、計測の事実は書かれていない）。(3) リモート遮断と HTML 内スクリプト非実行 — RemoteLoadBlocker（WKContentRuleList）と allowsContentJavaScript=false（DirectHTMLModeController）。RemoteLoadBlocker は fail-open。(4) git を知っているリンク解決と worktree 追従 — TrackedPathResolver / GitCommandFileIndex（indexFingerprint で再構築、worktree は別ルート）。(7) git バッジの 4 区分と色 — 緑=staged・オレンジ=unstaged・グレー=untracked・青=branchModified。細部の簡略化が 2 点: フォルダーは種別文字でなく • 固定、3 種類以上が混在すると上位 2 色のみ。
食い違い: (1) ライブリロード「0.2 秒で反映」 — 0.2 は FileWatcher.defaultDebounceDelay（検知から再読込開始までの待ち）で、読み込み・描画の時間は含まない。「約 0.2 秒」が正確。実測の遅延は記録なし。(5) Quick Open「空欄なら最近開いたファイルとブックマークが並ぶ」（shared.tsx） — 空欄時は initialCandidates が origin == .recent だけを返し、ブックマークは並ばない（QuickOpenCandidates.swift のコメントに「羅列ノイズを避ける」）。入力して絞り込んだときの検索対象には含まれる。(6)「続きは『さらに読み込む』で」（shared.tsx） — 実際のボタンは ja「続きを読み込む」/ en「Load More」（BefoldKit の Localizable.xcstrings の banner.loadMore）。
確認不能: ⌃⌘G の絞り込み挙動、「最大 100MB」の根拠（定数は TASK-692 前の調査で NormalizedTextCache.maxFileSizeBytes と一致を確認済み）。

AC2: 原因は node_modules 不在。退避して npx vitest run test/shortcuts.test.ts を 40 秒で打ち切ると、npx が固定外の vitest@5.0.3 をダウンロードしにいき終わらない（exit 142）。npm ci 後は固定の 4.1.10 で 17 件通る（shortcuts・file-types を含む）。
AC3: ja/en 2 組（ai-code-review 17 ブロック、medical-expenses 35 ブロック）で、ブロックの種類と数が一致。コードスパン・リンク・画像の対応も一致。数値の差は 4 ブロックだけで、いずれも数字と綴りの違い（6 と six、4 と four、5 年と five years、十数と a dozen）。ずれなし、修正不要。サイズ差は UTF-8 の日本語が 3 バイトであるため。
AC4: shortcuts.test.ts に逆方向（実装 ⊆ 表 ＋ 除外一覧）を追加。NOT_LISTED_ON_SITE に macOS 標準の 12 項目を理由つきで列挙し、除外一覧が実装に存在しない項目を残していないかも見る。追加直後に ⇧⌘G（前を検索）の漏れを検知し、表へ足して通した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
未検証だった 7 項目を裏取りし、一致 4・食い違い 3（0.2 秒の表現、Quick Open 空欄時のブックマーク、「さらに読み込む」の文言）を Notes に記録。vitest が止まる原因は node_modules 不在と再現で特定。記事の ja/en は構造が一致。ショートカット表の逆方向テストを足し、⇧⌘G の漏れを検知して直した。site の vitest 442 件・typecheck・lint・format:check で確認。食い違い 3 件の修正は含めていない。
<!-- SECTION:FINAL_SUMMARY:END -->
