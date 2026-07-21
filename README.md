# befold

macOS 向けファイルビューアアプリ。
多彩なフォーマットを開くだけで即座にレンダリング・プレビューする。

📖 **[紹介ページ（GitHub Pages）](https://ytommy109.github.io/befold/)**

## 機能

- **対応フォーマット**: Mermaid (.mmd) / Markdown (.md) / SVG / HTML / CSV / TSV のレンダリング表示、PNG / JPG / GIF / WebP / PDF の画像表示、50以上の言語のソースコード表示
- **レンダリング / ソース切替**: ⌘U でレンダリングとシンタックスハイライト付きソース表示を切替
- **ライブリロード**: ファイル保存で自動プレビュー更新（0.2s デバウンス）
- **タブ & セッション復元**: macOS ネイティブタブ対応、前回のタブ構成を自動復元
- **ズーム**: ⌘+ / ⌘- / ⌘0
- **アプリ内アップデート**: 新バージョン通知とワンクリック更新
- **ファイル参照ジャンプ**: ⌘+クリックでリンクや参照先ファイルを開く

## 動作要件

- macOS 14 (Sonoma) 以降

## インストール

1. [GitHub Releases](https://github.com/YTommy109/befold/releases/latest) から `befold-vX.Y.Z.dmg` をダウンロード
2. DMG を開き、`befold.app` を `/Applications` にコピーして起動

## コマンドラインからの利用

アプリメニューの「コマンドラインツールをインストール」を実行すると、ターミナルから `befold` コマンドで
ファイル/フォルダーを開けるようになります。

```bash
befold path/to/diagram.mmd    # ファイルを開く
befold --help                 # 利用可能なオプションを表示
```

`befold` コマンドは `/Applications/befold.app` 内の実行ファイルへの symlink です。
アプリを `/Applications` 以外へ移動した場合は、再度「コマンドラインツールをインストール」を実行してください。

## 開発

開発者向けのビルド手順・アーキテクチャ・技術スタックについては [開発ガイド](docs/dev/development.md) を参照してください。

## ライセンス

MIT
