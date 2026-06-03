# mmdview macOS アイコン デザイン仕様

## 概要

mmdview（Mermaid ダイアグラムプレビューアプリ）の macOS ネイティブアプリアイコン。

## デザイン仕様

### 背景
- 形状: macOS 標準角丸正方形（角丸半径 112/512 = 21.9%）
- 塗り: 3点グラデーション（左上→中央→右下）
  - `#1d4ed8`（ブルー）→ `#7c3aed`（パープル）→ `#0891b2`（シアン）
- サイズ基準: 512×512px viewBox

### フォアグラウンド（フローチャート）
縦フロー3ノード構成。上から下へ矢印で繋がる。

#### ノード（角丸四角形 × 3）
- 共通サイズ: 幅 216px、高さ 82px、角丸 22px
- 共通塗り: グラデーション `#f0abfc`（ピンク）→ `#a5f3fc`（水色）
- 配置:
  | ノード | x   | y   | opacity |
  |--------|-----|-----|---------|
  | 上     | 148 | 108 | 1.0     |
  | 中     | 148 | 248 | 0.88    |
  | 下     | 148 | 388 | 0.76    |

#### エッジ（白い縦線 + 矢印頭）
- 線: `stroke="white"`, `stroke-width="8"`, `opacity="0.8"`
- 矢印頭: `<polygon>` で直接描画（白、`opacity="0.85"`）
  - 幅 28px（中心 ±14px）、高さ 28px
- エッジ1（上ノード → 中ノード）:
  - 線: `(256,192)` → `(256,220)`
  - 矢印頭: `points="242,220 270,220 256,248"`
- エッジ2（中ノード → 下ノード）:
  - 線: `(256,332)` → `(256,360)`
  - 矢印頭: `points="242,360 270,360 256,388"`

### 装飾
- 上半分に白の薄いオーバーレイ（`opacity="0.04"`）でハイライト感を追加

## 成果物

### ファイル構成
```
static/icons/
  icon.svg          # マスター SVG（512×512 viewBox）
  icon.png          # 1024×1024 PNG（Retina 用）
  icon.icns         # macOS アイコンセット（全サイズ含む）
```

### .icns に含めるサイズ
| サイズ | ファイル名（iconset 内） |
|--------|------------------------|
| 16×16  | icon_16x16.png         |
| 32×32  | icon_16x16@2x.png      |
| 32×32  | icon_32x32.png         |
| 64×64  | icon_32x32@2x.png      |
| 128×128 | icon_128x128.png      |
| 256×256 | icon_128x128@2x.png   |
| 256×256 | icon_256x256.png      |
| 512×512 | icon_256x256@2x.png   |
| 512×512 | icon_512x512.png      |
| 1024×1024 | icon_512x512@2x.png |

## 実装方針

1. `static/icons/icon.svg` を作成（マスター SVG）
2. `cairosvg` または `rsvg-convert` で 1024×1024 PNG に変換
3. macOS 標準の `iconutil` コマンドで `.iconset` フォルダ → `.icns` に変換
4. `mmdview.spec` の `icon=None` を `icon='static/icons/icon.icns'` に変更
5. `pyproject.toml` にビルド用タスクを追加（オプション）

## 参照
- ビジュアルモックアップ: `.superpowers/brainstorm/96691-1780488205/content/icon-final-v6.html`
- PyInstaller 設定: `mmdview.spec:64`
