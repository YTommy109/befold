# モード切替時の検索状態リフレッシュ設計

<!-- derived-from ./2026-07-10-inline-search-design.md#概要 -->

## 概要

プレビュー内検索(Cmd+F)は「表示モードの切り替えとは独立に動き、切替時は新しい DOM に対して同じクエリ・トグルで自動的に再検索する」ことを [元設計](./2026-07-10-inline-search-design.md) で意図していたが、実装ではレンダリング→ソースモード方向の再検索呼び出しが漏れていた。本設計はこのギャップを埋め、あわせて「モード切替時は再検索後のマッチ位置をどうするか」を明文化する。

## 現状の問題

- `viewer.html` の `render()`(通常のレンダリング表示パス)は末尾で検索バーが開いていれば `_mmdFindRefresh()` を呼び、新しい DOM に対して再検索・件数更新・ハイライトを行う。
- 一方 `_renderSource()`(ソース表示パス)には同等の呼び出しがなく、レンダリング→ソースへの切替時は検索の件数・ハイライトが古い DOM を指したまま取り残される。
- 逆方向(ソース→レンダリング)は通常の `render()` を通るため `_mmdFindRefresh()` が働くが、既存の `_mmdFindRefresh()` は「ライブリロード時に現在位置をできるだけ維持する」ためのロジックであり、モード切替という文脈では位置維持に意味がない(DOM 構造がレンダリング結果とソースコードとで全く異なるため、同じインデックス番号が指す内容に連続性がない)。

## 方針(単純化の検討)

検索マッチ管理・ハイライト・件数表示のための新しい状態は追加しない。既存の「ライブリロード追従用リフレッシュ機構」`_mmdFindRefresh()` を、リセット挙動を選べるように最小限拡張して再利用する。

## 詳細設計

### 1. `_mmdFindRefresh()` の拡張(`viewer.html:612`)

```js
function _mmdFindRefresh(resetToFirst) {
  var previousIndex = resetToFirst ? 0 : _mmdFindCurrentIndex;
  _mmdFindRun();
  if (_mmdFindMatches.length > 0) {
    _mmdFindCurrentIndex = Math.min(Math.max(previousIndex, 0), _mmdFindMatches.length - 1);
    _mmdFindHighlightCurrent();
    _mmdFindUpdateCount();
  }
}
```

`resetToFirst` 省略時(ライブリロード時の既存呼び出し)は従来どおり現在位置を維持する。

### 2. モード切替の検出

`setViewMode(mode)`(`viewer.html:848`)で、渡された `mode` が現在の `_viewMode` と異なる場合に `_mmdModeJustSwitched = true` をセットしてから `_viewMode` を更新する。Swift 側は現状どおり `setViewMode` → `render()` の順で評価するだけでよく、Swift 側(`ViewerWebView.swift`)の変更は不要。

### 3. `render()` 末尾の呼び出し更新(`viewer.html:826`)

```js
if (_mmdFindIsOpen()) { _mmdFindRefresh(_mmdModeJustSwitched); }
_mmdModeJustSwitched = false;
```

### 4. `_renderSource()` への呼び出し追加(`viewer.html:830-843`)

`render()` と同じブロックを `_renderSource()` の末尾にも追加する。

## 動作仕様

- レンダリング→ソース、ソース→レンダリングのどちらの方向でモード切替しても、検索バーが開いていれば新しい DOM に対して自動的に再検索し、件数表示を更新し、1件目のマッチへハイライト・スクロールする。
- 同一モード内でのファイル内容更新(ライブリロード)は従来どおり現在位置をできるだけ維持する(挙動は変更しない)。
- クエリ文字列、および大文字小文字区別/単語単位/正規表現の3トグルはモード切替によってリセットされない(`_mmdFindOptions` / `_mmdFindQuery` には触れない)。
- 検索バー自体は、モード切替の前後を通じて開いたままの状態を維持する(閉じない)。

## 対象外

- 検索クエリやトグル状態のリセット(既存どおり維持する)
- ライブリロード時の位置維持ロジックの変更

## テスト

JS/WebView 層は自動テスト対象外(プロジェクト規約)。手動確認項目:

1. 検索バーを開いてクエリを入力した状態でレンダリング→ソースへ切替 → 新しい件数表示・1件目ハイライトになること
2. 同じ状態でソース→レンダリングへ切替 → 同様に1件目ハイライトへ戻ること
3. モード切替後もクエリ文字列・トグル状態(大文字小文字区別など)が保持されていること
4. 同一モード内でのファイル編集(ライブリロード)時、位置維持の既存挙動が壊れていないこと
