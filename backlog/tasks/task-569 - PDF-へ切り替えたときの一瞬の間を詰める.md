---
id: TASK-569
title: PDF へ切り替えたときの一瞬の間を詰める
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-29 22:23'
updated_date: '2026-08-30 03:19'
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
## 方針（2026-08-30 / 実測で作り直し）

タイルの到着時刻に依存しない形にする。**切り替え直後、同期で描いた静止画を面の上に
載せ、タイルが載るまでの白紙を消す。**

### 前提（すべて実測で裏づけ済み。詳細は Implementation Notes）

- 遅いのではなく**ばらつく**。現在の中央値 52.3ms は 1.15.1 の 99.1ms より速いが、
  18 回中 3 回が 274〜286ms へ跳ねる。1.15.1 は 18/18 が 76〜108ms で跳ねない。
- 跳ねた回も**アプリ側の仕事は +41.5ms で完了**している。差は PDFKit の非同期タイル
  描画の中だけ。メインスレッドは詰まっていない（4ms 周期のタイマが跳ねの間も走った）。
- **タイル到着を観測できる信号は無い。** `PDFPageView` の layer とその 4 枚の sublayer は
  `contents` が最後まで nil のまま（タイルは IOSurface へ直接行く）。`draw(_ page:to:)` の
  override も使えない（`super` が `@MainActor` で呼べない）。
- 単純な案は 2 つとも実測で棄却した。(a) 1 ページ目の同期描画で温める→跳ねは残り中央値
  +9ms 悪化。(b) 倍率適用がタイル要求を無効化しているというレース仮説→遅い回と速い回で
  `scaleFactor` の変更は 1 回ずつ・順序も同一で、支持されない。

### 実装前に決めたこと（`/review-design` の結果）

1. **置き場は `PDFSurfacePlaceholder`（新設）。** `ZoomingPDFView` に stored property 1 本で
   持たせる。行数回避ではなく、**購読と寿命を持つ別の関心**だから分ける
   （`ZoomingPDFView` は現在 170 行、そのまま足すと +50〜70 行・stored property +2）。
2. **install は必ず「古いものを外してから」の 1 関数にする。** `updateNSView` は連続の
   カーソル送りで追い越される。前の placeholder が残ると**前のファイルの絵が新しい
   ファイルの内容として見える**（チェック項目 8 そのもの）。面ごとに 1 枚しか
   存在しえない構造にし、連続 install で子ビューが 1 枚であることをテストで固定する。
3. **外す条件は `PDFSurfaceLayout` の 1 箇所へ収斂させる。** 面を動かす経路は
   `apply(zoom:to:)`（生成側・メニュー・ピンチ・`keepZoomAfterLayout` が全部通る）・
   `rotate(byDegrees:in:)`・`restore(fraction:in:)` の 3 つで、いずれも
   `PDFSurfaceLayout` にある。ここへ落とす処理を置けば列挙漏れが起きない
   （`rg 'pdfView.scaleFactor|setBoundsOrigin|\.rotation ='` で数えて確認する）。
   加えてスクロール（`boundsDidChange`）で外す。
4. **`layout()` では外さない。** install 直後にもう一度 layout が走ることがあり、
   「次の layout で外す」は早すぎて白紙が戻る。**install 時の bounds と変わったときだけ**外す。
   install は `layoutSubtreeIfNeeded()` の後（倍率・位置が確定した後）に限る。
5. **上限は 400ms（保険であって正しさには効かない）。** 実測の最悪値 293ms に対する余裕。
   静止画は下に描かれる内容と同一なので、外れるのが遅れても見た目は変わらない。
   上限は「万一ずれたときに固まらない」ためだけに置く。
6. **`isVisible == false` のときは出さない・載っていれば外す**（ADR 0002 段 5 と揃える）。
   opacity 0 の面の上に静止画を残さない。
7. **1 ページも描けない文書（暗号化・破損）は placeholder 無しで従来どおり。**

### 何を描くか

`pdfView.visiblePages` を、`pdfView.convert(page.bounds(for:), from: page)` で得た矩形へ描く。
**位置・倍率・回転は PDFKit から取る**（`PDFSurfaceLayout` の規則をこちら側へ写さない）。
コストは実測 0.87〜6.5ms／ページ。

### 検証

- 自動テストで守れるのは install / 除去の分岐まで。**「白紙が見えない」ことは自動テストでは
  測れない**（GUI 層はテスト対象外）。前後の実測（`.tmp/t569/sampler`）を証拠として残す。
- 対処の前後で、同じ測り方の値（18 回、中央値・最大・跳ねの回数）を並べて記録する。
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

## 測り直し（2026-08-30 / 実シナリオ + 画面のピクセル）

### 測り方（前回の測り方の誤りを直したもの）

- **終点はページの中身が画面に出た時刻**。窓の中央 200x200 を高頻度でキャプチャし、
  暗い画素が現れた時刻を取る。`PDFView.draw(_ dirtyRect:)` は面が塗られた時刻でしかないので
  終点に使わない。`draw(_ page:to:)` の override は使えない——`nonisolated override` 自体は
  書けるが、`super.draw(page, to:)` が `@MainActor` なので呼べずビルドが通らない
  （実測: sending 'page' risks causing data races）。
- **起点は実シナリオ**。サイドバーで ↓ を送る（`CGEvent` / `osascript`）。
  前回の FileWatcher の rename 追従による再現は **debounce 0.2s をそのまま測り込む**ため
  端から端の測定には使えない（`FileWatcher.defaultDebounceDelay = 0.2`）。
- 前の内容が消えた時刻も同時に取り、**白紙が見えている区間**を分離した。
- 計装一式は `.tmp/t569/`（`sampler.swift` / `compare.sh` / `presskey.swift`）。

### 結果（150 ページ・約 150KB の PDF を 18 回、どちらも Release）

| | 中央値 | 範囲 | 白紙の区間 |
| --- | --- | --- | --- |
| 1.15.1（WebKit プラグイン） | 99.1ms | 76.5〜108.4ms | 52〜93ms |
| 現在（PDFKit） | 52.3ms | 32.4〜286.1ms | 14〜67ms |

**典型値では現在のほうが速い（52ms 対 99ms）。ただし現在の版は二峰性で、
18 回中 3 回（17%）が 274〜286ms に跳ねる。** 1.15.1 は 18 回すべて 76〜108ms に収まり、
跳ねが 1 回も無い。ユーザーが報告した「0.1〜0.2 秒はっきり見える空白」はこの跳ねに当たる。
**速さではなく、ばらつきが体感を悪くしている。**

なお 1.15.1 にも白紙の区間は 52〜93ms ある（PDF 面へ切り替わってから中身が出るまで）。
白紙そのものが新しく生まれたわけではない。

### 跳ねはアプリ側ではない（区間ログとの突き合わせ）

アプリ側に絶対時刻（`DispatchTime` の uptime）のログを入れ、サンプラの時刻と突き合わせた。
キー押下からの経過（+）で示す。

| 区間 | 速い回 | 跳ねた回 |
| --- | --- | --- |
| `loadContent` | -24〜-7 | -14 |
| `performLoad start` | +3.4〜+22.4 | +17.9 |
| `pipeline done` | +4.0〜+23.0 | +18.5 |
| `applied` | +4.8〜+24.0 | +19.6 |
| `updateNSView` 開始〜終了 | +5.6〜+31.7 | +20.7〜+27.9 |
| `PDFView.draw` | +21.0〜+41.5 | +41.4 |
| **中身が出る** | **+33.9〜+46.8** | **+286.1** |

**跳ねた回もアプリ側の仕事は +41.5ms で全部終わっている。** 差は PDFKit の
非同期タイル描画の中だけにある（速い回はタイルが 1 フレームで届き、跳ねた回は約 245ms 遅れる）。
2 回目の `PDFView.draw` は起きていないので、タイルはレイヤへ直接載っている。

### 試して棄却した単純化（実測つき）

`updateNSView` の中で 1 ページ目を `page.thumbnail(of:for:)` で同期に 1 回描き、
PDFKit を温める案。**効かない**——18 回中 1 回が 290.7ms に跳ね（跳ねは残る）、
中央値は 52.3ms → 61.3ms と約 9ms 悪化した。1 行で済む案だったので先に試した。

### 次の一手

タイルの到着時刻に依存しない形にするしかない（Implementation Plan の placeholder）。
着手前に `/review-design` を回す。

## 対処と、その前後の実測（2026-08-30）

`PDFSurfacePlaceholder` を新設し、文書を差し替えた直後に**可視ページを同期で焼いた静止画**を
面の上へ載せるようにした。タイルがいつ載るかを知ろうとせず、載っても困らない絵を先に置く形。

外すのは面が動く事実だけ——スクロール（`boundsDidChange`）・倍率（`PDFSurfaceLayout.apply(zoom:)`）・
回転（同 `rotate(byDegrees:in:)`）・面の寸法変化・次の差し替え。上限 0.4 秒は保険で、
静止画は下に描かれる内容と同一なので正しさには効かない。

### 実測（150 ページ・約 150KB の PDF、サイドバーの ↓、18 回、すべて Release）

| | 中央値 | 最小 | 最大 | 200ms 超の跳ね |
| --- | --- | --- | --- | --- |
| 1.15.1（WebKit プラグイン） | 99.1ms | 76.5ms | 108.4ms | 0/18 |
| 対処前 | 52.3ms | 32.4ms | 293.1ms | 3/18 |
| **対処後** | **41.2ms** | **25.3ms** | **50.4ms** | **0/18** |

**跳ねが消え、中央値・最小・最大のすべてで対処前と 1.15.1 の両方を下回った。**

### 実装で踏んだこと（記録）

3 つとも実測で見つけたもので、どれも「入れたのに効かない」形だった。

1. **`PDFView.visiblePages` はこの時点では常に空。** 文書を入れて `layoutSubtreeIfNeeded()` を
   済ませた直後でも 0 件を返す。`page(for:nearest:)` で面の上の点から引かせる形に替えた。
2. **`PDFPage.draw(with:to:)` はページ座標の原点を考慮しないとずれる。** `bounds(for:)` の
   原点が 0 でない文書で中身が矩形の外へ出て、静止画が白紙のままになった。
   一度 `thumbnail(of:for:)` に逃げたが、ポイント寸法でラスタライズされて
   2 倍解像度のビットマップでぼやけるうえ、install が 15.6ms かかって
   **切り替え全体の中央値が 52.3ms → 69.0ms と悪化**した。原点を戻す変換を足して
   直接描画へ戻し、焼く範囲もページの矩形だけに絞って install は 2.16ms になった。
3. **PDFKit はレイアウトのたびに自分のサブビューを積み直す。** 載せたときだけ最前面に
   しても下へ潜り、18 回中 2 回だけ静止画が見えず 222〜238ms の白紙が残った。
   `noteLayout` で毎回 `addSubview(_:positioned:relativeTo:)` により上げ直して解決。

### 検証

- `swift test`: 1812 tests / 294 suites すべて通過（`PDFSurfacePlaceholderTests` を 8 件追加）。
- swiftlint: main とのベースライン差分ゼロ（54 件 → 54 件、真の新規なし）。
- 計装（`SwitchTrace` / 各 mark / `PDFView.draw` の override / `LayerProbe`）は全撤去済み。
- 計測用の一式は `.tmp/t569/`（`sampler.swift` / `compare.sh` / `nav2/`）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF 切り替えの間を区間ごとに実測し、最大の PDF 固有区間へ対処した。

実測（151 ページ / 128KB、窓内の .md → .pdf 切替、2 回とも再現）では、切り替え全体 49ms のうち PDF の実処理（読み込み・ハッシュ・PDFDataProbe・PDFDocument 生成・レイアウト）は約 7ms しかなく、残りは (1) メインアクターの空き待ち 22〜28ms と (2) AppKit の表示サイクル待ち 12〜16ms だった。(1) は .md でも同じ待ちを踏むので PDF 固有ではない。

(2) に対し PDFPreviewView.updateNSView の layoutSubtreeIfNeeded 直後へ pdfView.display() を足し、最初のフレームを同じ実行の中で描くようにした。レイアウト完了から最初の描画までが 12.4/16.0ms → 0.24/0.27ms、切り替え全体が 48.95/48.67ms → 34.8/34.65ms（−14.2ms / −29%）。displayIfNeeded は 2 回に 1 回しか効かず不採用。

窓内切り替えの再現には FileWatcher の rename 追従を使った（同一 inode のまま .md へ PDF を書き、.pdf へ改名）。新規ウィンドウで開く測り方は窓の初回表示を含み 111ms 対 49ms とずれるため使えない。

残る (1) は共通経路の実行順序の変更になるため別タスクとする。swift test 1804 tests 全通過、swiftlint ベースライン差分ゼロ、計装は全撤去。
<!-- SECTION:FINAL_SUMMARY:END -->
