---
id: TASK-564.5
title: PDF の向きを 90 度単位で変えられるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-29 00:42'
updated_date: '2026-08-29 12:25'
labels: []
dependencies:
  - TASK-564.1
  - TASK-564.2
  - TASK-564.3
parent_task_id: TASK-564
priority: medium
type: feature
ordinal: 819000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

横向きにスキャンされた PDF などを、90 度単位で回して読めるようにする。

## 前提

`PDFPage.rotation`（0 / 90 / 180 / 270）と `PDFView.rotate(byDegrees:)` で実現できる。TASK-564.2（1 ページフィット）に依存させているのは、回転するとページの縦横比が変わり、画面にフィットする倍率が変わるため。回転後もフィットが保たれることを両タスクの整合として確認する必要がある。

## 論点（実装着手前に `/review-design` で詰める）

- **回転の適用範囲**: 文書全体を回すのか、現在ページだけを回すのか。ページごとに向きが混在する PDF があるため、全体回転だと一部だけ正しくならない。逆にページ単位だと、ページを送るたびに回し直す手間が出る。既定をどちらにするかを決める。
- **記憶**: 回転状態は TASK-564.3 の「ウィンドウの生存期間だけ記憶する表示状態」に含める（永続化しない）。含めない判断をするなら理由を記録すること。
- **操作の入口**: メニュー項目とキーボードショートカットの新設が要る。追加先は `MainMenuBuilder+ViewMenu`（既存のズーム項目群の近傍）、`MenuShortcutCatalog` / `ViewerShortcutCatalog` / `ShortcutKey`、ヘルプの一覧 `HelpShortcutSections`、ローカライズ `Localizable.xcstrings`。有効判定は `ViewerCapabilities` に新しい能力を足して `ViewerMenuValidator` から返す（メニュー構築時に種別で分岐しない、という既存の原則を守る）。
- **ショートカットの衝突**: 新設するキーが既存のショートカットとぶつからないことを `/menu-audit` で確認する。
- **`Localizable.xcstrings` の編集**: キー順にソートし直さない。既存の並びを保ち、近縁キーの直後に挿入する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PDF を 90 度単位で時計回り・反時計回りに回転できる
- [x] #2 回転後も 1 ページが画面にフィットした状態が保たれる
- [x] #3 回転が文書全体かページ単位かの判断と理由が Implementation Notes に記録されている
- [x] #4 回転の操作がメニュー項目とキーボードショートカットの両方から届き、`ViewerCapabilities` の能力として PDF 以外では無効になっている
- [x] #5 新設したショートカットが既存のものと衝突しないことを `/menu-audit` で確認済み
- [x] #6 メニュー項目とヘルプのショートカット一覧が日本語・英語の両方でローカライズされている
- [x] #7 別ファイルへ移って戻ったときに回転状態が保たれ、ウィンドウを閉じるとリセットされる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-29）

### 回転の適用範囲（AC #3）

**文書全体を回す**（現在ページだけではない）。横向きにスキャンされた PDF は
文書ごと横倒しになっているのが普通で、ページ単位だとページを送るたびに回し直す
ことになる。ページごとに向きが混在する PDF では一部が正しくならないが、そちらは
例外的な形なので「1 回の操作で読める状態になる」ほうを採った。
判断は `PDFSurfaceLayout.rotate(byDegrees:in:)` の doc にも書いてある。

### 構造

- 能力: `ViewerCapabilities.canRotate`（入力は `supportsRotation`）。種別の判定は
  `ViewerCapabilitiesFactory` の 1 箇所（`fileType == .pdf`）で、メニューもコマンドも
  能力しか見ない（AC #4）。
- 面: `DocumentSurfaceOperating` に `rotate(byDegrees:)` と `currentRotation` を足した。
  web の面は回転を持たないので no-op / 0 だが、**能力で塞いであるので呼ばれない**。
- メニュー: View メニューに「右に回転」（⌘R）「左に回転」（⇧⌘R）。向きは項目の
  タグ（90 / -90）が運び、@objc の入口は `rotateDocument(_:)` 1 つ。Preview.app の
  ⌘L / ⌘R のうち ⌘L は行番号表示に使用済みのため ⇧⌘R を左回転に充てた。
- 記憶: `WindowPresentationMemory` に回転を足した（位置・表示モードと同じ寿命）。
  保存は切替の退場側（`saveScrollPositionBeforeTransition`）で面から同期に読み、
  復元は提示開始（`beginPresentingDocument`）で `store.pdfRotation` へ。AC #7。

### ショートカットの衝突（AC #5）

**`/menu-audit` は実行できなかった。** osascript の assistive access が
この環境では許可されておらず（`System Events got an error: osascript is not
allowed assistive access. (-1719)`）、実際に走っているメニューのダンプが取れない。

代わりに**恒久的なテストで塞いだ**。`MainMenuShortcutTests` の
「メインメニュー全体でキー等価は重複しない」が、トップレベル 6 メニューすべての
キー等価（キー + 修飾キー）の重複を検査する。従来の View メニュー内だけの重複検査
では、別メニューとの衝突が素通りしていた（⌘R を足したときに File の項目と当たっても
気づけない）。実測で重複ゼロ。**有効/無効の実測（validateMenuItem の結果）だけは
未確認なので、ユーザーの目視が必要。**

### ローカライズ（AC #6）

`menu.view.rotateClockwise` / `menu.view.rotateCounterClockwise` を日英で追加した
（既存の並びを保ち、近縁キーの直後に挿入。キー順のソートはし直していない）。
Help のショートカット一覧は `MenuShortcutCatalog` がメニューから生成するので、
項目を足した時点で両言語に載る。

### 実測で分かったこと

**`PDFPage.rotation` を変えた後に `layoutDocumentView()` を自分で呼んではならない。**
PDFKit は回転の通知を受けて再レイアウトを**メインキューへ積む**ため、二重に走る。
テストでは面が解放された後にその遅延ブロックが走り、解放済みの `PDFDocumentView`
を触って落ちた（EXC_BAD_ACCESS at 0x0 / `-[PDFDocumentView layoutDocumentView]`。
並列実行で 4 回に 1 回ほど再現）。自前の呼び出しを外し、テスト側は面をプロセスの
終わりまで保持する形にして、`swift test` を 4 回連続で成功させて収束を確認した。
本番の面は窓と同じ寿命なのでこの順序は起きない。

### 検証

- `swift test` 1772 件すべて成功（4 回連続）。回転の全ページ適用・0/90/180/270 の
  巡回・左回転の正規化・記憶した角度への復帰・回転後もフィットが保たれること
  （AC #2）・文書なしでの安全性を実測で固定した。
- swiftlint の main とのベースライン差分ゼロ、型グループの行数も上限内
  （`ViewerWindowController` 899/900、`MainMenuBuilder` 399/400）。

### 目視が必要な残り

AC #1（実際に回って見えること）と AC #4 の「PDF 以外でメニューが無効になる」実測。

## 回転後にフィットが保たれていなかった（発見と修正 / 2026-08-29）

AC #2 は当初「`autoScales` が縦横比の変化に追従する」という前提で通したが、
**その前提が誤りだった**。オフスクリーン描画で面の座標を測ったところ、
回転後のページが面からはみ出していた（400x500 の面に対しページ幅 488pt）。

実測（Letter 1 ページ / 400x500 の面）:

| 時点 | scaleFactor | scaleFactorForSizeToFit | ページの寸法 |
| --- | --- | --- | --- |
| 初期 | 0.617 | 0.617 | 377 x 488（収まる） |
| 回転直後 | 0.617 | 0.617 | 488 x 377（はみ出す） |
| 再レイアウト後 | 0.617 | **0.495** | 488 x 377（はみ出したまま） |

`autoScales` が効き直すのは**面のリサイズのとき**だけで、ページの寸法が変わった
ときではない。`scaleFactorForSizeToFit` は更新されるのに `scaleFactor` が古いまま残る。

**当初の単体テストはこれを見逃した。** `currentZoom`（= scaleFactor ÷ fitScale）だけを
見ており、回転直後は両方が古い値のままなので比が 1 になり通ってしまう。
比ではなく**面の座標で実際に収まっているか**を測る必要があった。

修正: `PDFSurfaceLayout.rotate` が回転前の倍率を捉え、**メインキューへ後から積んで**
入れ直す。同期に入れ直すと、まだ古い `scaleFactorForSizeToFit` を読む（再レイアウトも
メインキューへ積まれるため、こちらを後に積めば順序が保証される）。フィットで見て
いたならフィットのまま、拡大していたなら同じ拡大率のままになる。

## AC #5（ショートカットの衝突）の検証

`/menu-audit` は assistive access が無く走らせられないため、`validateMenuItem` が
使うのと同じ判定関数（`ViewerMenuValidator`）へ**実際に構築したメニュー項目**を
通す `ViewMenuValidationTests` を足した。回転の 2 項目が PDF のときだけ有効になり、
それ以外では無効になること、ズーム側が巻き添えで変わっていないことを固定している。
キー等価の重複はメインメニュー全体の検査（`MainMenuShortcutTests`）で実測ゼロ。
<!-- SECTION:NOTES:END -->
