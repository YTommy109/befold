import AppKit
import SwiftUI

/// PDF の面に重なる SwiftUI の中で使う一行入力欄。**AppKit の `NSTextField` を直接置き、
/// 自分で first responder を取りに行く。**
///
/// **SwiftUI の `TextField` + `@FocusState` はこの面では効かない。** 実機で計測したところ、
/// `isInputFocused = true` を入れても窓の first responder は `ZoomingPDFView` のままで、
/// `@FocusState` の値も false のままだった（実測 / TASK-578.2）。マウスでフィールドを
/// クリックしても移らない。原因は、AppKit がホストする `PDFView` の上に SwiftUI を
/// 重ねている構造そのものにある。
///
/// **この型があるのは、同じ穴を 3 回開けないため（TASK-579）。** 1 回目はページ番号の
/// 入力欄（TASK-578.2）、2 回目は検索バーで、どちらも「SwiftUI の `TextField` を置いた」
/// という同じ書き方から生まれた。個別に直すのをやめ、この面に置く入力欄は必ずこの型を
/// 通す形にした。次に誰かが `TextField` を置いても、動かないことにすぐ気づけるよう
/// `PDFSurfaceTextFieldTests` が両方の呼び出し元を押さえている。
///
/// **閉じた後にどこへフォーカスを戻すかは、この型では決めない。** 戻し先は常に
/// 「いま読んでいる面」で、`PDFViewProxy.focusSurface()` が持つ（理由はそちらの doc）。
struct FocusClaimingTextField: NSViewRepresentable {
    @Binding var text: String
    /// 空のときに薄く出す文字列。nil なら出さない。
    var placeholder: String?
    /// 文字の寄せ。ページ番号は右寄せ、検索語は自然な向き。
    var alignment: NSTextAlignment = .natural
    /// nil なら `NSTextField` の既定。桁を揃えたい用途では等幅の数字を渡す。
    var font: NSFont?
    /// Enter。ページ番号なら確定、検索なら次のヒットへ。
    let onSubmit: () -> Void
    /// Esc。
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = alignment
        field.font = font
        field.placeholderString = placeholder
        field.lineBreakMode = .byClipping
        field.cell?.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        claimFocus(field)
    }

    /// **窓へ入った後で移す。** 置かれた直後の `updateNSView` ではまだ窓に入っておらず、
    /// その場で呼んでも移らない（実測: `field.window` が nil。1 周待ってから呼ぶと
    /// `makeFirstResponder` が true を返し、窓の first responder がフィールドエディタ
    /// （`NSTextView`）になる / TASK-578.2）。
    ///
    /// 既に自分が持っているときは取り直さない。`updateNSView` は 1 文字ごとに走るので、
    /// 毎回取り直すと選択位置とキャレットが壊れる。
    private func claimFocus(_ field: NSTextField) {
        DispatchQueue.main.async {
            guard let window = field.window,
                  window.firstResponder !== field,
                  window.firstResponder !== field.currentEditor()
            else { return }
            window.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusClaimingTextField
        init(parent: FocusClaimingTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        /// **Enter と Esc は AppKit 側で受ける。** SwiftUI の `onSubmit` /
        /// `onExitCommand` は first responder が SwiftUI 側に無い以上そもそも呼ばれない。
        func control(
            _ control: NSControl, textView _: NSTextView, doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
