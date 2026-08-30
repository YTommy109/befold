import AppKit
import SwiftUI

/// ページ番号を打ち込むための一行フィールド（TASK-578.2）。
///
/// **SwiftUI の `TextField` + `@FocusState` では打ち込めない。** この面は AppKit が
/// ホストする `PDFView` の上に重なる SwiftUI で、実機で計測したところ
/// `isInputFocused = true` を入れても窓の first responder は `ZoomingPDFView` のまま、
/// `@FocusState` の値も false のままだった（実測: `firstResponder=ZoomingPDFView` /
/// `focusState=false`）。マウスでフィールドをクリックしても移らない。
/// **そこで AppKit のフィールドを直接置き、`makeFirstResponder` で明示的に移す。**
///
/// 確定（Enter）と取り消し（Esc）も AppKit 側で受ける。`onSubmit` / `onExitCommand` は
/// first responder が移っていない以上そもそも呼ばれない。
///
/// **閉じたら first responder を面へ返す。** 返さないとフィールドが消えた後に
/// キーの行き先が無くなり、スペースや矢印でスクロールできなくなる。
struct PageNumberField: NSViewRepresentable {
    @Binding var text: String
    /// Enter。
    let onSubmit: () -> Void
    /// Esc。
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.lineBreakMode = .byClipping
        field.cell?.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        // **窓へ入った後で移す。** 置かれた直後の `updateNSView` ではまだ窓に
        // 入っておらず、その場で呼んでも移らない（実測: `field.window` が nil。
        // 1 周待ってから呼ぶと `makeFirstResponder` が true を返し、窓の first
        // responder がフィールドエディタ（`NSTextView`）になる / TASK-578.2）。
        DispatchQueue.main.async {
            guard let window = field.window,
                  window.firstResponder !== field,
                  window.firstResponder !== field.currentEditor()
            else { return }
            context.coordinator.previousResponder = window.firstResponder
            window.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PageNumberField
        /// フィールドを出す前の first responder（＝面）。閉じたらここへ返す。
        weak var previousResponder: NSResponder?

        init(parent: PageNumberField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl, textView _: NSTextView, doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                restoreResponder(from: control)
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                restoreResponder(from: control)
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        /// 面へ first responder を返す。フィールドが消えるより先に返さないと、
        /// 窓の first responder が消えた View を指したままになる。
        private func restoreResponder(from control: NSControl) {
            guard let window = control.window, let previous = previousResponder else { return }
            window.makeFirstResponder(previous)
        }
    }
}
