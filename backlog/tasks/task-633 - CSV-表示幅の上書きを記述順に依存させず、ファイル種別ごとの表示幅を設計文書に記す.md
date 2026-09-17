---
id: TASK-633
title: CSV 表示幅の上書きを記述順に依存させず、ファイル種別ごとの表示幅を設計文書に記す
status: To Do
assignee: []
created_date: '2026-09-17 06:01'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/pull/679'
modified_files:
  - BefoldApp/BefoldKit/Resources/style.css
  - BefoldApp/viewer-test/viewer-csv-columns.test.ts
  - docs/dev/native-app-design.md
priority: low
type: chore
ordinal: 830000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #679（CSV/TSV の表示幅をウィンドウに合わせる）のレビューで出た 3 点。#679 は取り込み、これらは #679 の上に積む後続 PR で対応する。

1. **上書きが CSS の記述順に依存している。** #679 は `#diagram-wrap.csv-body { max-width: 100%; }` を足したが、`_renderCsv`（`viewer-src/renderers.ts`）は `markdown-body` と `csv-body` を両方付けるため、`#diagram-wrap.markdown-body { max-width: 980px; }` と詳細度が同じで、style.css の後ろにあるから勝っているだけ。並べ替えると黙って 980px に戻る。`#diagram-wrap.markdown-body.csv-body` にすれば記述順に依存しない。

2. **回帰テストが宣言の存在しか見ていない。** `viewer-csv-columns.test.ts` の追加アサーションは style.css の文字列に `#diagram-wrap.csv-body { ... max-width: 100%; }` が含まれるかを正規表現で見るだけで、1 の並べ替えでも緑のまま。守りたいのは「CSV 表示では 980px の上限が効かない」こと。1 を詳細度で直したうえで、そのセレクタ（markdown-body と csv-body の両方を含む）を検査する形にするか、カスケードを評価できる方法で確かめる。

3. **ファイル種別ごとの表示幅が現在仕様に無い。** `docs/dev/native-app-design.md` には Markdown / XSLT の 980px、CSV・コードの全幅、画像のフィットなどの幅の仕様が書かれていない。#679 の PR 本文にある「ファイル種別ごとの幅の挙動」の表が材料になる（Markdown・XSLT の 980px と `#diagram-wrap` の 100% は style.css と照合済み。その他の行は取り込み時にコードで裏を取る）。

レビュー時の仕様判断（記録）: 980px は Markdown 本文の読み幅であり、CSV に掛かっていたのは表の装飾を借りるための markdown-body 付与の副作用。表は github-markdown-css で width: max-content のため全幅化しても行は引き伸ばされない。列の少ない CSV が左余白位置から始まる見た目の変化は、コード表示と同じ振る舞いとして許容する（中央寄せは列数で開始位置が動くため採らない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CSV 表示の max-width 上書きが markdown-body の 980px より詳細度で勝ち、style.css 内の記述順に依存しない
- [ ] #2 上書きを markdown-body の規則より前へ移す、または詳細度を元に戻すと、viewer のテストが落ちる
- [ ] #3 docs/dev/native-app-design.md に、ファイル種別ごとの表示幅（読み幅の上限の有無・フィット・横スクロール）が現在仕様として記載されている
<!-- AC:END -->
