# befold

macOS 向けファイルビューアアプリ。
多彩なフォーマットを開くだけで即座にレンダリング・プレビューする。

📖 **[紹介ページ](https://befold.tommy109.workers.dev/?ref=readme)**

## 機能

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

## 動作要件

- macOS 14 (Sonoma) 以降

## インストール

1. [最新版をダウンロード](https://befold.tommy109.workers.dev/download?ref=readme)
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

各ライブラリのライセンス全文は [THIRD_PARTY_LICENSES.md](BefoldApp/BefoldKit/Resources/THIRD_PARTY_LICENSES.md) に収録しており、
同ファイルは befold.app にも同梱されています。

## ライセンス

MIT（[LICENSE](LICENSE) を参照）
