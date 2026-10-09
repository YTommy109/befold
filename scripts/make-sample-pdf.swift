// scripts/make-sample-pdf.swift
//
// PDF 内検索のスクリーンショット用に sample/sample.pdf を作る。
// cupsfilter で作ったテキスト PDF は PDFKit の検索ハイライトが文字位置からずれるため、
// CoreText で描く(ずれない)。使い方: swift scripts/make-sample-pdf.swift sample/sample.pdf
import AppKit
import CoreText

let body = """
befold の読み込みメモ

befold はファイルを監視し、変更を同じプロセスの中で描き直す。
大きなファイルはチャンクに分けて読むので、最初の画面はすぐに出る。

チャンク読み込み
ビューアは先頭のチャンクだけを描画し、残りは保持しない。
続きが必要なときは、truncated バナーから利用者が追加で読み込む。

ファイル監視
変更は DispatchSource で検知し、0.2 秒デバウンスしてから反映する。
ビューアはスクロール位置を保ったまま描き直す。

検索
⌘F で文書の中を検索できる。
一致した箇所はすべて強調され、Return で次の一致へ移る。
"""

var box = CGRect(x: 0, y: 0, width: 595, height: 842)
guard let ctx = CGContext(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, mediaBox: &box, nil) else { exit(1) }
ctx.beginPDFPage(nil)
let font = NSFont(name: "HiraginoSans-W3", size: 13) ?? NSFont.systemFont(ofSize: 13)
let style = NSMutableParagraphStyle()
style.lineSpacing = 6
let text = NSAttributedString(string: body, attributes: [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.black])
let frame = CTFramesetterCreateFrame(
    CTFramesetterCreateWithAttributedString(text), CFRangeMake(0, 0),
    CGPath(rect: box.insetBy(dx: 56, dy: 64), transform: nil), nil
)
CTFrameDraw(frame, ctx)
ctx.endPDFPage()
ctx.closePDF()
