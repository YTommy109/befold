---
id: TASK-569
title: PDF へ切り替えたときの一瞬の間を詰める
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-29 22:23'
updated_date: '2026-08-30 00:52'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 826000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーをカーソルキーで送って .md から .pdf へ切り替えると、1.15.1 (1640) と比べて一瞬の間がある（ユーザー報告 / 2026-08-30）。実用上の問題は無いが、旧バージョンのほうが快適という評価。

TASK-567 で「切り替え直後の 1 フレームがフィット前の倍率で描かれ、縮む過程が見える」問題は解消済み（倍率を最初の描画より前に確定させた）。**残っているのは描画の前後にある間**であり、原因は未特定。

実測で分かっている、原因**ではない**もの（TASK-567 で測定済み）:

- 面そのものの描画は PDFKit のほうが速い。231 ページ / 800x900 で 1 フレーム描くまで、WebKit 内蔵プラグイン 49〜122ms に対し PDFKit 7〜8ms
- フィット倍率の計算は 1 回 0.024ms（231 ページ）。縦フィットにしたことのコストではない
- 読み込み経路は 1.2MB の PDF で読み込み 0ms・ハッシュ 0ms・PDFDocument 生成 0ms。`PDFDataProbe` だけ初回 22ms（PDFKit の遅延初期化。2 回目以降は 0ms）
- ページの影は 1 フレームあたり約 30ms 掛かるが、TASK-567 で無効化済み

未確認の候補:

- 読み込みが非同期タスクを一往復する区間（`ViewerStore.loadContent` → `apply`）
- SwiftUI の状態反映が 1 フレーム挟まる区間（`showsPDF` の切り替えと面の可視化）
- `PDFDataProbe` と表示側で `PDFDocument` を 2 回作っている点（probe はバックグラウンド、表示は MainActor。PDFDocument が Sendable でないため意図的に分けてある）

進め方: 推測で手を入れず、一時ログで区間ごとの時刻を取り、どこに間があるかを特定してから対処する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーで .md から .pdf へ送ったときの、操作から最初の PDF フレームまでの時間が区間ごとに実測され、どこに間があるかが特定されている
- [ ] #2 特定した区間に対する対処が入り、対処の前後の実測値が記録されている（対処不要と判断した場合はその根拠が実測付きで記録されている）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 方針（2026-08-30 / ユーザー確認済み）

`display()` は revert 済み。**タイルが届くまで、同期描画した 1 ページ目を placeholder として見せる**方向で進める。

### 前提（実測・裏付けつき）

- **空白の正体**: PDFKit はページの中身をバックグラウンドの `PDFTilePool.workQueue` で非同期に描く。`PDFView.draw` はタイルを待たずに戻るため、届くまで面は背景色のまま。証拠は `ZoomingPDFView` へ `draw(_ page:to:)` の override を足したときのクラッシュスタック（`PDFKit.PDFTilePool.workQueue` から `@objc ZoomingPDFView.draw(_:to:)` が呼ばれて SIGTRAP）。
- **同期描画は安い**（130 ページ・125KB / 単体プログラムでの実測）: `page.thumbnail(of: 800x900, for: .mediaBox)` が初回 6.51ms、2 回目以降 0.87ms / 0.76ms。`doc.page(at: 0)` は 0.06ms。
- **測る終点を間違えない**: `PDFView.draw(_ dirtyRect:)` は面が塗られた時刻であって、ページの中身が出た時刻ではない。以後この区間の評価に使わない。

### 未解決の設計論点（着手時に `/review-design` で詰める）

1. **placeholder をいつ外すか。** PDFKit にタイル完了の通知は無い。候補: (a) 一定時間後、(b) 次の表示サイクル、(c) タイルが載ったことを何らかの観測可能な事実で判定する。**(a) の固定待ちは「推測で手を入れない」というこのタスクの方針に反するので、採るなら根拠を実測で出すこと。**
2. **どのページを描くか。** 復元するスクロール位置（`scrollPositionToRestore`）によっては 1 ページ目ではない。`PDFSurfaceLayout` が位置とページの対応を持っているので、そこから決める。
3. **倍率・回転との整合。** placeholder は `initialZoom` と `rotation` を反映した見た目でなければ、外した瞬間にずれて見える。
4. **置き場所。** `PDFPreviewView` に閉じるか、`ZoomingPDFView` が自前で持つか。ADR 0009 の「宛先の決定は `DocumentSurfaces` だけ」を崩さないこと。
5. **`PDFView` の override は危険。** PDFKit がバックグラウンドから呼ぶメソッド（`document` プロパティ、`draw(_ page:to:)`）を `@MainActor` 隔離のまま override すると SIGTRAP で落ちる。placeholder の実装でこれらに触らない形にするか、触るなら `nonisolated` で書けることを先に確かめる。

### 検証の作り直し

- **終点はページの中身が出た時刻にする。** 安全に測る方法をまず決める（`draw(_ page:to:)` の override は上記のとおり落ちる）。決まらないうちは、ユーザーによる目視（「空白が見えるか」）を唯一の判定にする。
- 対処の前後で、同じ測り方の値を並べて記録する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## WebKit 経路へ戻す案について（実測 / 2026-08-30）

「WebKit のままで当初の目的を達成できなかったのか」という問いに対し、実測で確かめた
結果を ADR 0009 の Context へ追記した。結論は「できない」——プラグインの中身は
スクリプトから見えず（`document.embeds` は 1 個見えるが `window.scrollY` は 0 のまま）、
表示位置の記憶と 90 度回転は原理的に実装できない。

あわせて、私が以前書いた「WebKit は GPU 合成で速い」は**検証していない推測**だったので、
ADR の Consequences にその旨を明記した。もし描画経路が遅さの本体だと分かった場合は、
`PDFPage.draw` で自前にタイルレイヤーへ描く案が残っている（規模は大きい）。
**この判断はこのタスクの実測が出てから行うこと。** いまの時点で分かっているのは
「面の描画自体は速い（影なしで 1 フレーム 4〜7ms、スクロール 5 フレームで 11〜14ms）」
であり、間はその前後の区間にある。

## 区間の実測（2026-08-30）

### 測り方

`SwitchTrace`（一時。撤去済み）で各区間の絶対時刻をファイルへ追記した。NSLog は出力先が環境で変わって取り逃したため、指定ファイルへ直接書く形にした。

**窓内の切り替えをキー入力なしで再現する方法**: `FileWatcher` の rename 追従を使う。同じ inode のまま `s*.md` へ PDF のバイト列を上書きし（`cat sample.pdf > s.md`）、続けて `mv s.md s.pdf` とすると `handleRename → openFile` が走り、**新しい窓を作らずに** `.md → .pdf` の切り替えが起きる。新規ウィンドウで開く測り方は「窓の初回表示」を含むため別物になる（実際 111ms 対 49ms と倍以上ずれた）。他窓の親ディレクトリ監視に巻き込まれないよう、専用サブディレクトリで行う。

対象: 151 ページ / 128KB の PDF。Debug ビルド。

### 結果（窓内切り替え / 2 回とも再現）

| 区間 | switch a | switch b |
| --- | --- | --- |
| `loadContent` 予約 → `performLoad` 開始 | 19.5ms | 17.4ms |
| `performLoad` → pipeline 復帰 | 7.7ms | 5.3ms |
| pipeline 復帰 → `state applied` | 0.17ms | 0.14ms |
| `state applied` → `updateNSView` 開始（SwiftUI） | 2.6ms | 2.8ms |
| `updateNSView`（`PDFDocument` 生成＋回転＋倍率＋レイアウト） | 6.5ms | 7.0ms |
| **レイアウト完了 → 最初の描画** | **12.4ms** | **16.0ms** |
| **合計（`loadContent` → 最初の描画）** | **48.95ms** | **48.67ms** |

pipeline の内側も割った（別の測定）。`ContentLoader.loadData` が 0.15〜0.47ms、`PDFDataProbe` が 0.11〜0.35ms。**タスクに書かれていた「probe 初回 22ms」は PDFKit の遅延初期化で、2 回目以降は誤差**。読み込み・ハッシュ・probe・`PDFDocument` 生成・レイアウトを全部足しても約 7ms しかない。

### どこに間があるか

**PDF の実処理ではない。** 間は次の 2 種類に分かれる。

1. **メインアクターの空き待ち（17〜20ms ＋ 5〜8ms）。** `loadContent` の `Task { await performLoad(...) }` は MainActor を継承するため、切り替えで積まれた他の仕事（サイドバー同期・ツールバー更新・SwiftUI 再評価）が捌けるまで**開始すらしない**。復帰側も同様。**これは PDF 固有ではない**——同条件の `.md` でも `loadContent → performLoad` が 24〜52ms かかっており、同じ待ちを踏んでいる。
2. **AppKit の表示サイクル待ち（12〜16ms）。** `updateNSView` が倍率・位置を確定してレイアウトまで済ませても、実際の描画は次の表示サイクルまで来ない。**これは PDF 固有の区間**で、対処できる最大のもの。

## 対処と、その前後の実測

`PDFPreviewView.updateNSView` の `layoutSubtreeIfNeeded()` の直後に `pdfView.display()` を足し、最初のフレームを同じ実行の中で描くようにした。

| | 対処前 | 対処後 |
| --- | --- | --- |
| レイアウト完了 → 最初の描画 | 12.4ms / 16.0ms | **0.24ms / 0.27ms** |
| 合計（`loadContent` → 最初の描画） | 48.95ms / 48.67ms | **34.8ms / 34.65ms** |

**−14.2ms（−29%）。各条件 2 回ずつで再現。** 描画そのものは 5.4〜5.5ms で、待っていた 12〜16ms より短い。

`displayIfNeeded()` も試したが採らなかった。2 回のうち 1 回しか描画が起きず（PDFKit がまだ dirty を立てていない瞬間がある）、効く / 効かないが再現しない。`display()` は無条件なので揺れない。`updateNSView` 自体が `contentRevision` の変化でしか走らないため、無条件でも文書 1 つにつき 1 回。

副作用として、通常の表示サイクルによる 2 回目の描画（約 19ms 後）は残る。同じ内容なので見た目の破綻は無く、増える仕事は 1 文書あたり 1 回・約 5ms。

## 残っている最大の区間（このタスクでは対処しない）

上の 1.（メインアクターの空き待ち、合計 22〜28ms）が残る。**PDF 固有ではなく `.md` でも同じ**なので、このタスク（PDF 切替の間）の範囲を超える。対処するなら `loadContent` の `Task` を MainActor 継承から外す形になるが、共通経路の実行順序を変える変更なので `/review-design` を通す必要がある。`Task.detached` はこのリポジトリでは pre-commit で禁止されている（`OK: Task.detached の使用なし`）ため、nonisolated なヘルパー経由になる。別タスクとして起票するのが妥当。

## 自動検証

- `swift test`: 1804 tests / 293 suites すべて通過。
- swiftlint: main とのベースライン差分ゼロ（54 件 → 54 件）。
- 計装（`SwitchTrace.swift` / `PipelineTrace` / 各 mark / `ZoomingPDFView.draw` の override）は全撤去済み。撤去後のビルドでアプリを起動し、PDF を開いてクラッシュしないことを確認した。

## 計測中に踏んだこと（記録）

一時計装のバグでアプリを 1 回クラッシュさせた（SIGTRAP / arithmetic overflow）。`SwitchTrace` の基準時刻を `static let` の遅延初期化に任せたため、`DispatchTime.now() - base` の `base` が now より後に初期化され、符号なし減算がアンダーフローした。アプリ本体の問題ではない。

## 再オープン: 対処が効いていない（ユーザー報告 / 2026-08-30）

「1.15.1 と比べて遅く感じる。PDF が表示されるまで、何も表示されない**空白ページ**が 0.1〜0.2 秒はっきり見える」

**上の実測は測る対象を間違えていた。** 私が「最初の描画」として計測した `PDFView.draw(_ dirtyRect:)` は**面が塗られた時刻**であって、**ページの中身が出た時刻ではない**。背景だけを塗った空白フレームも「描画」として数えていた。したがって「34.7ms で最初のフレーム」は、ユーザーが見ている空白の終わりを表していない。34.7ms は空白が**始まる**までの時間に近い。

### 空白の正体（実測 / クラッシュスタックが証拠）

ページの中身の描画時刻を測ろうとして `ZoomingPDFView` に `draw(_ page:to:)` の override を足したところ SIGTRAP で落ちた。そのスタックが答えだった。

```
Thread 7  PDFKit.PDFTilePool.workQueue
  _dispatch_assert_queue_fail
  swift_task_checkIsolatedSwift
  @objc ZoomingPDFView.draw(_:to:)
  PDFKit  -[PDFTilePool _renderTileForRequest:]
  PDFKit  -[PDFTilePool requestPDFTileSurfaceForTarget:forPage:...]
```

**PDFKit はページの中身をバックグラウンドのタイルプール（`PDFTilePool.workQueue`）で非同期に描いている。** `PDFView` の `draw` は先に戻り、タイルが届くまで面は背景色のまま。これが見えている空白。

（この override が落ちたのは、`@MainActor` 隔離のメソッドをバックグラウンドキューから呼ばれたため。CLAUDE.md が `document` プロパティについて警告しているのと同じ罠を、別のメソッドで踏んだ。ユーザーのアプリを 2 回クラッシュさせた。）

### 同期描画のコスト（実測 / 単体プログラム）

130 ページ・125KB の PDF で、PDFKit を直接呼んで計測した。

| 操作 | 時間 |
| --- | --- |
| `PDFDocument(data:)`（プロセス内初回。PDFKit の遅延初期化を含む） | 43.0ms |
| `doc.page(at: 0)` | 0.06ms |
| `page.thumbnail(of: 800x900, for: .mediaBox)` 初回 | 6.51ms |
| 同 2 回目・3 回目 | 0.87ms / 0.76ms |
| 全 130 ページの `bounds` 走査 | 2.36ms |

**1 ページを同期で描くのは 1〜7ms しかかからない。** つまり「タイルを待つ間だけ、自分で描いた 1 ページ目を見せる」は現実的なコストで成立しうる。

### `display()` の扱い（要再検討）

コミット 47dd9aab で入れた `pdfView.display()` は、**空白のフレームを 12〜16ms 早く塗る**方向に働く可能性がある。効果として測った「切り替え全体 49ms → 34.7ms」は、上のとおり終点の取り方が誤っていた。この症状に対しては無効か、わずかに悪化させている疑いがある。正しい終点（タイルが届いた時刻）で測り直すまで、採否を確定できない。

## 中断時点（2026-08-30）

- コミット 47dd9aab の `pdfView.display()` を revert した（ソース変更のみ。タスクファイルの記述は履歴として残す）。`swift test` 1804 tests / 293 suites 全通過。
- 作業ツリーに計装は残っていない。
- 次にやること: 上の Implementation Plan の論点 1（placeholder をいつ外すか）から。ここが決まらないと実装に入れない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF 切り替えの間を区間ごとに実測し、最大の PDF 固有区間へ対処した。

実測（151 ページ / 128KB、窓内の .md → .pdf 切替、2 回とも再現）では、切り替え全体 49ms のうち PDF の実処理（読み込み・ハッシュ・PDFDataProbe・PDFDocument 生成・レイアウト）は約 7ms しかなく、残りは (1) メインアクターの空き待ち 22〜28ms と (2) AppKit の表示サイクル待ち 12〜16ms だった。(1) は .md でも同じ待ちを踏むので PDF 固有ではない。

(2) に対し PDFPreviewView.updateNSView の layoutSubtreeIfNeeded 直後へ pdfView.display() を足し、最初のフレームを同じ実行の中で描くようにした。レイアウト完了から最初の描画までが 12.4/16.0ms → 0.24/0.27ms、切り替え全体が 48.95/48.67ms → 34.8/34.65ms（−14.2ms / −29%）。displayIfNeeded は 2 回に 1 回しか効かず不採用。

窓内切り替えの再現には FileWatcher の rename 追従を使った（同一 inode のまま .md へ PDF を書き、.pdf へ改名）。新規ウィンドウで開く測り方は窓の初回表示を含み 111ms 対 49ms とずれるため使えない。

残る (1) は共通経路の実行順序の変更になるため別タスクとする。swift test 1804 tests 全通過、swiftlint ベースライン差分ゼロ、計装は全撤去。
<!-- SECTION:FINAL_SUMMARY:END -->
