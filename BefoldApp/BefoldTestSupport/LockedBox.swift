import Foundation

/// NSLock で保護したスレッドセーフな可変ボックス。
/// Sendable クロージャからのカウント・記録に使う。
public final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public func get() -> Value {
        lock.withLock { value }
    }

    public func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }

    public func update(_ transform: @Sendable (inout Value) -> Void) {
        lock.withLock { transform(&value) }
    }
}
