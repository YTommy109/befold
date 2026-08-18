<!-- markdownlint-disable MD033 -->
<!-- MD033/no-inline-html: GitHub の README はヒーロー画像の中央寄せ・スクリーンショットの
     幅指定・機能一覧の折りたたみに inline HTML を要する（Markdown 記法では表現できない）。
     このファイルは GitHub の表示専用なので、ここだけ許可する。 -->

<div align="center">

# befold

**開く。すぐ描かれる。それだけ。**

Mermaid / Markdown / SVG / CSV / 画像 / PDF / ソースコードを開くだけで即座にレンダリングする、
macOS ネイティブのファイルビューア。ライブリロード・あいまいファイル検索・git 差分の並列表示つき。

[![Release](https://img.shields.io/github/v/release/YTommy109/befold?label=release&color=0a7)](https://github.com/YTommy109/befold/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=fff)](#動作要件)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[**ダウンロード**](https://befold.degino.com/download?ref=readme) ·
[**紹介ページ**](https://befold.degino.com/?ref=readme) ·
[English README](README.md)

<img src="site/public/images/screenshot-1.png" alt="befold で表示した Mermaid のフローチャート（サイドバー表示あり）" width="900">

</div>

---

## なぜ befold か

プレビュー手段はたいてい何かを諦めることになる。そのエディタでしか動かないプラグインか、
手で更新するブラウザのタブか、私物のファイルを貼り付ける Web サービスか。

befold は、ただファイルを開く単体の macOS アプリ。プロセス内でレンダリングし、ファイルを監視して、
保存した瞬間に描き直す。エディタもサーバーもアップロードも要らない。

## こんなときに使う

**AI コーディングエージェントの出力をその場で確認する。**
エージェントは Mermaid の図や Markdown の仕様書を次々に吐く。`befold docs/design.mmd` で
レンダリング済みの状態で開き、エージェントが書き換えるたびにウィンドウが自動で描き直される。
mermaid.live に貼り直す必要はない。

**エディタの隣にライブプレビューを置いて仕様書を書く。**
片側に befold、片側にエディタ。保存すると 0.2 秒でプレビューが更新される。
プラグインではないので、どのエディタでも使える。

**知らないリポジトリを読み解く。**
`⌘P` でツリー内のどのファイルにもあいまい検索で飛び、`⌘+クリック` でリンクや参照先ファイルを開き、
`⌘[` / `⌘]` で履歴を行き来する。IDE に期待する移動手段が、設定不要のビューアにある。

**変更を差分で読む。**
git リポジトリ内なら、ソース表示に差分を並べて出し、変更されたファイルをサイドバーに印で示す。

**Finder から、何も開かずにプレビューする。**
QuickLook 拡張を同梱しているので、`.mmd` や `.md` にスペースキーを押すだけでレンダリング結果が出る。

## 表示できるもの

| | |
|---|---|
| <img src="site/public/images/screenshot-3.png" alt="befold の Markdown プレビュー" width="380"><br>**Markdown** — GitHub 風スタイル、コードブロックはハイライト付き | <img src="site/public/images/screenshot-1.png" alt="befold で表示した Mermaid のフローチャート" width="380"><br>**Mermaid** — フローチャート / シーケンス / クラス / ER / 状態遷移 |
| <img src="site/public/images/screenshot-2.png" alt="befold で表示した SVG の図" width="380"><br>**SVG・画像** — PNG / JPG / GIF / WebP / BMP / ICO / PDF も | <img src="site/public/images/screenshot-4.png" alt="befold で表示した CSV の表" width="380"><br>**CSV / TSV** — 表として描画、大きなファイルは段階描画 |
| <img src="site/public/images/screenshot-5.png" alt="befold のソースコード表示" width="380"><br>**ソースコード** — 30 以上の言語・49 拡張子、`⌘U` で切替 | <img src="site/public/images/screenshot-7.png" alt="befold のソース表示に並べた git の差分" width="380"><br>**git 差分** — ソース表示にそのまま並べて表示 |
| <img src="site/public/images/screenshot-6.png" alt="befold の Quick Open パネル" width="380"><br>**Quick Open** — `⌘P` であいまい検索、キーボードだけで開く | <img src="site/public/images/screenshot-8.png" alt="befold のサイドバーに出る変更ファイルの git ステータス" width="380"><br>**git ステータス** — 変更されたファイルをサイドバーに表示 |

## 動作要件

macOS 14 (Sonoma) 以降

## インストール

1. [最新版をダウンロード](https://befold.degino.com/download?ref=readme)
2. DMG を開き、`befold.app` を `/Applications` にコピーして起動

## コマンドラインからの利用

アプリメニューの「コマンドラインツールをインストール」を実行すると、ターミナルから `befold` コマンドで
ファイル/フォルダーを開けるようになります。

```bash
befold path/to/diagram.mmd     # ファイルを開く（複数指定するとそれぞれ別ウィンドウで開く）
befold path/to/dir             # フォルダー内の対応ファイルをサイドバー付きで開く
befold --check path/to/file    # 開かずに、開けるファイルかどうかだけを判定する
befold --bookmark path/to/file # 開かずにブックマークへ追加する
befold --help                  # 利用可能なオプションを表示
```

開き方の表示オプションも指定できます（`--line-numbers` / `--no-line-numbers`、
`--sidebar` / `--no-sidebar`、`--source` / `--preview`、
`--sort folders-first|alphabetical`）。これらは開くファイルに対する指定なので、
パスと一緒に渡してください（既に開いているファイルを指定した場合は、そのウィンドウへ反映されます）。
`--hidden-files` / `--no-hidden-files` だけはアプリ全体の設定のため、パス無しでも指定できます。
ハイフンで始まるパスを開くときは `--` の後ろに置いてください（例: `befold -- -notes.md`）。

`befold` コマンドは `/Applications/befold.app` 内の実行ファイルへの symlink です。
アプリを `/Applications` 以外へ移動した場合は、再度「コマンドラインツールをインストール」を実行してください。

<details>
<summary><b>機能の一覧</b></summary>

### 表示

- **対応フォーマット**: Mermaid (.mmd / .mermaid) / Markdown (.md / .markdown) / SVG / HTML / CSV / TSV のレンダリング表示、PNG / JPG / GIF / WebP / BMP / ICO / PDF の表示、30 以上の言語（49 拡張子）のシンタックスハイライト付きソース表示
- **レンダリング / ソース切替**: ⌘U でレンダリング結果とソース表示を切替（⌘L で行番号の表示切替）
- **ライブリロード**: ファイル保存で自動プレビュー更新（0.2s デバウンス）
- **大きなファイルの段階描画**: Markdown / CSV・TSV / ソースコードは先頭から順に読み込んで描画するため、巨大ファイルでも待たされない
- **ズーム**: ⌘+ / ⌘- / ⌘0
- **ページ内検索**: ⌘F で検索、⌘G / ⇧⌘G で前後の一致へ移動
- **Finder クイックルック**: QuickLook 拡張を同梱しており、Finder でスペースキーを押すだけでアプリを開かずにプレビューできる

### ファイルの行き来

- **サイドバー**: ⌘S で開閉。同じフォルダーのファイルを一覧し、フォルダー優先／アルファベット順の並び替え、名前での絞り込み、⌃⌘H で不可視ファイルの表示切替ができる。git リポジトリ内なら相対パスの基準をリポジトリルートに合わせる
- **Quick Open**: ⌘P でパスをあいまい検索し、キーボードだけでファイルを開く
- **ファイル参照ジャンプ**: ⌘+クリックでリンクや参照先ファイルを開く。⌘[ / ⌘]（または二本指スワイプ）で戻る・進む
- **ブックマーク**: ⌘B でよく開くファイルに印を付け、ファイルメニューから開き直す
- **最近使った項目 / リポジトリ**: 直近のファイルに加え、リポジトリ単位でも前回のタブ構成ごと開き直せる

### ウィンドウとアプリ

- **タブ & セッション復元**: macOS ネイティブタブ対応、前回のウィンドウ・タブ構成を自動復元
- **設定**: ソース表示に使うコードフォントのファミリーとサイズを変更できる（⌘,）
- **アプリ内アップデート**: 新バージョン通知とワンクリック更新
- **ヘルプ**: 機能説明・キーボードショートカット一覧・AI コーディングエージェント連携の手引きをヘルプメニューから参照できる

</details>

## 謝辞

befold の表示機能は、以下のオープンソースライブラリに支えられています。作者と貢献者の皆さんに感謝します。

| ライブラリ | 役割 | ライセンス |
| --- | --- | --- |
| [Mermaid](https://github.com/mermaid-js/mermaid) | Mermaid ダイアグラムのレンダリング | MIT |
| [markdown-it](https://github.com/markdown-it/markdown-it) | Markdown のパースとレンダリング | MIT |
| [highlight.js](https://github.com/highlightjs/highlight.js) | ソース表示のシンタックスハイライト | BSD-3-Clause |
| [DOMPurify](https://github.com/cure53/DOMPurify) | レンダリング前の HTML サニタイズ | Apache-2.0 / MPL-2.0 |
| [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) | Markdown 表示のスタイル | MIT |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | アプリ内アップデート | MIT |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | `befold` コマンドの引数解析 | Apache-2.0 |
| [libgit2](https://github.com/libgit2/libgit2) | git 差分・ステータスの取得 | GPLv2 with linking exception |

各ライブラリのライセンス全文は [THIRD_PARTY_LICENSES.md](BefoldApp/BefoldKit/Resources/THIRD_PARTY_LICENSES.md) に収録しており、
同ファイルは befold.app にも同梱されています。

## ライセンス

MIT（[LICENSE](LICENSE) を参照）
