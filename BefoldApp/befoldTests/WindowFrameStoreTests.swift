@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct WindowFrameStoreTests {
    /// 新規の隔離 defaults 上に store を組み立てる。テストをまたいで defaults を共有したい場合は
    /// 呼び出し元で defaults を保持し、必要な回数だけこのファクトリへ渡し直す。
    private func makeStore(defaults: UserDefaults = makeIsolatedDefaults(prefix: "WindowFrameStoreTests"))
        -> (store: WindowFrameStore, defaults: UserDefaults)
    {
        (WindowFrameStore(defaults: defaults), defaults)
    }

    @Test
    func frameDescriptorIsNilWhenUnsaved() {
        let (store, _) = makeStore()

        #expect(store.frameDescriptor(for: URL(fileURLWithPath: "/tmp/diagram.mmd")) == nil)
    }

    @Test
    func setFrameDescriptorPersistsPerFileAcrossInstances() {
        let (store, defaults) = makeStore()
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        store.setFrameDescriptor("100 100 800 600 0 0 1920 1080", for: url)

        #expect(makeStore(defaults: defaults).store.frameDescriptor(for: url) == "100 100 800 600 0 0 1920 1080")
    }

    @Test
    func frameDescriptorsAreIndependentPerFile() {
        let (store, _) = makeStore()
        let first = URL(fileURLWithPath: "/tmp/first.mmd")
        let second = URL(fileURLWithPath: "/tmp/second.md")

        store.setFrameDescriptor("frame-a", for: first)
        store.setFrameDescriptor("frame-b", for: second)

        #expect(store.frameDescriptor(for: first) == "frame-a")
        #expect(store.frameDescriptor(for: second) == "frame-b")
    }

    @Test("rename で旧パスのフレームが新パスへ引き継がれ旧キーは消える")
    func migrateFrameDescriptorMovesValueToNewKey() {
        let (store, _) = makeStore()
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        store.setFrameDescriptor("frame-old", for: old)

        store.migrateFrameDescriptor(from: old, to: new)

        #expect(store.frameDescriptor(for: new) == "frame-old")
        #expect(store.frameDescriptor(for: old) == nil)
    }

    @Test("保存値のないファイルの migrate は新パスに影響しない")
    func migrateFrameDescriptorWithoutSavedValueIsNoop() {
        let (store, _) = makeStore()
        let old = URL(fileURLWithPath: "/tmp/old.mmd")
        let new = URL(fileURLWithPath: "/tmp/new.mmd")
        store.setFrameDescriptor("frame-new", for: new)

        store.migrateFrameDescriptor(from: old, to: new)

        #expect(store.frameDescriptor(for: new) == "frame-new")
    }

    @Test("未操作時は最後に調整したフレームは nil")
    func lastUserAdjustedFrameDescriptorIsNilWhenUnsaved() {
        let (store, _) = makeStore()

        #expect(store.lastUserAdjustedFrameDescriptor == nil)
    }

    @Test("recordUserAdjustedFrame はファイル単位の値と最後に調整したフレームの両方を更新する")
    func recordUserAdjustedFrameUpdatesBothPerFileAndLastAdjusted() {
        let (store, defaults) = makeStore()
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

        store.recordUserAdjustedFrame("frame-x", for: url)

        let reloaded = makeStore(defaults: defaults).store
        #expect(reloaded.frameDescriptor(for: url) == "frame-x")
        #expect(reloaded.lastUserAdjustedFrameDescriptor == "frame-x")
    }

    @Test("setFrameDescriptor(ウィンドウオープン時の記録)は最後に調整したフレームを書き換えない")
    func setFrameDescriptorDoesNotAffectLastUserAdjustedFrameDescriptor() {
        let (store, _) = makeStore()
        store.recordUserAdjustedFrame("frame-a", for: URL(fileURLWithPath: "/tmp/a.mmd"))

        store.setFrameDescriptor("frame-b", for: URL(fileURLWithPath: "/tmp/b.mmd"))

        #expect(store.lastUserAdjustedFrameDescriptor == "frame-a")
    }

    @Test("自ファイルの保存値があればそれを使う")
    func initialFrameDescriptorUsesOwnSavedValueWhenPresent() {
        let (store, _) = makeStore()
        let url = URL(fileURLWithPath: "/tmp/own.mmd")
        store.setFrameDescriptor("frame-own", for: url)

        #expect(store.initialFrameDescriptor(for: url, lastActivePathKey: "/tmp/other.mmd") == "frame-own")
    }

    @Test("自ファイルの保存値がなければ直近アクティブだったウィンドウのフレームを使う")
    func initialFrameDescriptorFallsBackToLastActiveWindowFrame() {
        let (store, _) = makeStore()
        let activePath = URL(fileURLWithPath: "/tmp/active.mmd")
        store.setFrameDescriptor("frame-active", for: activePath)

        let result = store.initialFrameDescriptor(
            for: URL(fileURLWithPath: "/tmp/new.mmd"), lastActivePathKey: activePath.normalizedPathKey
        )

        #expect(result == "frame-active")
    }

    @Test("直近アクティブなウィンドウの記録も自ファイルの保存値もなければ最後に調整したフレームを使う")
    func initialFrameDescriptorFallsBackToLastUserAdjustedFrameDescriptor() {
        let (store, _) = makeStore()
        store.recordUserAdjustedFrame("frame-elsewhere", for: URL(fileURLWithPath: "/tmp/somewhere-else.mmd"))

        let result = store.initialFrameDescriptor(for: URL(fileURLWithPath: "/tmp/new.mmd"), lastActivePathKey: nil)

        #expect(result == "frame-elsewhere")
    }

    @Test("記録が何もなければ nil (呼び出し側で既定のカスケード配置にフォールバックする)")
    func initialFrameDescriptorIsNilWhenNothingRecorded() {
        let (store, _) = makeStore()

        #expect(store.initialFrameDescriptor(for: URL(fileURLWithPath: "/tmp/new.mmd"), lastActivePathKey: nil) == nil)
    }
}
