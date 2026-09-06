import AppKit
@testable import befold
import BefoldKit
import Testing

/// `.slide` が「明示的な 1 経路からしか渡らない」ことの担保(TASK-593.2)。
///
/// `OpenDisposition` はリンククリックの修飾キー解釈表でもある。スライド窓を
/// 修飾キーで開けるようにする決定はしていないので、修飾キーの表から `.slide` が
/// 出ないことを固定する。ここが破れると、⌘⇧クリックが黙ってスライド窓を開き始める。
struct OpenDispositionSlideTests {
    @Test("修飾キーの組み合わせからは .slide が生成されない")
    func modifierKeysNeverProduceSlide() {
        for commandKey in [true, false] {
            for shiftKey in [true, false] {
                let disposition = OpenDisposition(commandKey: commandKey, shiftKey: shiftKey)

                #expect(
                    disposition != .slide,
                    "command=\(commandKey) shift=\(shiftKey) が .slide を返した"
                )
            }
        }
    }

    @Test("修飾キーの表そのものは従来どおり")
    func modifierTableIsUnchanged() {
        #expect(OpenDisposition(commandKey: true, shiftKey: true) == .newWindow)
        #expect(OpenDisposition(commandKey: true, shiftKey: false) == .newTab)
        #expect(OpenDisposition(commandKey: false, shiftKey: true) == .currentTab)
        #expect(OpenDisposition(commandKey: false, shiftKey: false) == .currentTab)
    }
}
