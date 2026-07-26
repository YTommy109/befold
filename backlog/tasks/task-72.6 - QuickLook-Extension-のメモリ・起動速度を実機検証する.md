---
id: TASK-72.6
title: QuickLook Extension のメモリ・起動速度を実機検証する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-07-19 06:44'
updated_date: '2026-07-26 11:55'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 216000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
大きめのmermaid/markdown/巨大コードファイルでappexのメモリ使用量・応答時間を計測する。appexのメモリ上限に対して余裕があるか確認し、必要であればQuickLook専用の追加サイズ上限を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 代表的な大きめファイル種別(mermaid/markdown/巨大コード)でのメモリ・起動速度の計測結果が記録されている
- [ ] #2 appexのメモリ上限に対する余裕があることを確認している、または追加のサイズ上限が導入されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. コード上の上限を確認する(行指向=100MB/チャンク、非行指向=10MB/全量)
2. 上限付近を突く計測用ファイルを sample/large/ に生成する(git 管理外)
3. appex に暫定計測を入れる(ファイル名・サイズ・経過時間・自プロセスの phys_footprint)
4. 外部サンプラーで appex と WebContent プロセスのピークメモリを記録する
   (appex からは別プロセスである WebContent のメモリを取得できないため)
5. Finder で 1 巡プレビューしてもらい、両方のログを突き合わせる
6. 結果を記録し、追加のサイズ上限が必要か判断する
7. 暫定計測を削除する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 計測結果(2026-07-26 / macOS 26.5.2 / befold 1.7.3(748))

Finder の QuickLook で 1 ファイルずつプレビューし、appex 側の自己計測(経過時間・
phys_footprint)と外部サンプラー(appex と WebContent の RSS)を突き合わせた。
qlmanage -p は preparePreviewOfFile を呼ばないため Finder 経路でしか計測できない。

### 行指向(CSV/コード) — 問題なし
| ファイル | 経過 | appex | WebContent ピーク |
| --- | --- | --- | --- |
| code_10mb.py | 0.29s | 14.7MB | 118MB |
| code_99mb.py | 0.33s | 14.6MB | 118MB |
| code_101mb.py | 0.05s | 14.7MB | 41MB (fileTooLarge で正しく拒否) |

先頭チャンクしか描画しない設計が効いており、99MB でも 0.33 秒・WebContent 118MB。
Data は memory-map されるため appex の footprint も増えない。上限 100MB のままでよい。

### 非行指向(markdown) — サイズにほぼ比例
| サイズ | 経過 | WebContent ピーク |
| --- | --- | --- |
| 1MB | 1.51s | 901MB |
| 2MB | 2.16s | 1.57GB |
| 4MB | 3.30s(タイムアウト) | 2.24GB |
| 6MB | 3.31s(タイムアウト) | 3.28GB |
| 9MB | 3.34s(タイムアウト) | 4.17GB |
| 11MB | 0.06s | 41MB (fileTooLarge で正しく拒否) |

### mermaid — ノード数依存でサイズ上限が効かない
| ノード数 | サイズ | 経過 | WebContent ピーク |
| --- | --- | --- | --- |
| 250 | 6KB | 0.67s | 359MB |
| 500 | 12KB | 1.07s | 465MB |
| 1000 | 25KB | 2.37s | 706MB |
| 2000 | 53KB | 3.26s(タイムアウト) | 1.39GB |

### 判定
- appex 本体のピークは 331MB で、メモリ上限には十分余裕がある(AC#1/#2 前半を満たす)
- 破綻するのは WebContent 側。体感で「表示されない」と誤解するのは
  oneShotRenderTimeout(3秒)に到達した組(markdown 4MB 以上 / mermaid 2000 ノード)と一致した

### 対応(AC#2 後半)
1. ContentLoader.maxOneShotTextFileSizeBytes(2MB)を新設し、oneShotLoad: true の
   ときだけ非行指向に適用。本体アプリの 10MB は据え置き(据え置きを担保するテストも追加)
2. 描画がタイムアウト後も続く間「レンダリング中…」を表示し、完了したら消す。
   完了判定は evaluateJavaScript の応答(描画中は JS メインスレッドが占有される)。
   mermaid はサイズ上限で防げないため、こちらで体感を担保する

### 注意
計測用の markdown はコードブロックが密で highlight.js に対して重い内容のため、
実文書では数値が小さくなる可能性がある。2MB という閾値は保守的な側に倒している。

### 派生
本体アプリでも同じ全量読み込み経路を通るため実測したところ、9MB の markdown で
WebContent が 3.06GB に達した。ユーザーが直接遭遇する不具合のため GitHub Issue
#307 として起票した(本タスクのスコープ外)。
<!-- SECTION:NOTES:END -->
