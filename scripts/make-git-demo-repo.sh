#!/usr/bin/env bash
# scripts/make-git-demo-repo.sh
#
# 配布サイトの git 機能スクリーンショット用に、使い捨ての git リポジトリを作る。
#
# 既存 6 枚は sample/ 配下の実ファイルを撮っているが、git のスクリーンショット
# （差分表示・サイドバーのステータスバッジ）には「ブランチでの変更 / staged /
# unstaged / untracked が同時に揃ったワークツリー」が要る。befold 自身の
# リポジトリを汚さずに再現するため、専用のリポジトリをここで組み立てる。
#
# 生成される状態:
#   main                        … LRUCache のサンプル一式
#   feature/eviction-policy     … LRUCache.swift / EvictionPolicy.swift を変更（branchModified）
#   Sources/Metrics.swift       … unstaged
#   Sources/Store.swift         … staged
#   Sources/TTLPolicy.swift     … untracked
#
# 使い方: scripts/make-git-demo-repo.sh [出力先]
#   出力先の既定は "${TMPDIR:-/tmp}/befold-git-demo/lru-cache"。
#   既存ディレクトリは毎回消して作り直す（撮影のたびに同じ状態にするため）。
#   生成したパスを標準出力へ 1 行で返す。
set -euo pipefail

target="${1:-${TMPDIR:-/tmp}/befold-git-demo/lru-cache}"
rm -rf "$target"
mkdir -p "$target/Sources" "$target/Tests"
cd "$target"

git init -q -b main
git config user.email "demo@example.com"
git config user.name "befold demo"

cat > README.md <<'EOF'
# LRUCache

A small least-recently-used cache for expensive computations.
EOF

cat > Sources/LRUCache.swift <<'EOF'
import Foundation

/// A simple LRU (Least Recently Used) cache for expensive computations.
final class LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var storage: [Key: Value] = [:]
    private var usageOrder: [Key] = []

    init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
    }

    func value(for key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    func insert(_ value: Value, for key: Key) {
        if storage[key] == nil && storage.count >= capacity {
            evictLeastRecentlyUsed()
        }
        storage[key] = value
        touch(key)
    }

    private func touch(_ key: Key) {
        usageOrder.removeAll { $0 == key }
        usageOrder.append(key)
    }

    private func evictLeastRecentlyUsed() {
        guard !usageOrder.isEmpty else { return }
        let oldest = usageOrder.removeFirst()
        storage.removeValue(forKey: oldest)
    }
}
EOF

cat > Sources/EvictionPolicy.swift <<'EOF'
import Foundation

/// Decides which entry leaves the cache when it is full.
enum EvictionPolicy {
    case leastRecentlyUsed
    case leastFrequentlyUsed

    var description: String {
        switch self {
        case .leastRecentlyUsed: "LRU"
        case .leastFrequentlyUsed: "LFU"
        }
    }
}
EOF

cat > Sources/Metrics.swift <<'EOF'
import Foundation

/// Counts hits and misses so callers can tune the capacity.
struct CacheMetrics {
    private(set) var hits = 0
    private(set) var misses = 0
    private(set) var evictions = 0

    /// Share of lookups that were served from the cache, in the range 0...1.
    var hitRate: Double {
        let total = hits + misses
        return total == 0 ? 0 : Double(hits) / Double(total)
    }

    /// One-line summary for the benchmark output.
    var summary: String {
        let percentage = Int((hitRate * 100).rounded())
        return "\(hits) hits / \(misses) misses (\(percentage)%), \(evictions) evicted"
    }

    mutating func recordHit() { hits += 1 }
    mutating func recordMiss() { misses += 1 }
    mutating func recordEviction() { evictions += 1 }
}
EOF

cat > Sources/Store.swift <<'EOF'
import Foundation

/// Thread-safe wrapper around the cache storage.
final class Store<Key: Hashable, Value> {
    private var entries: [Key: Value] = [:]
    private let lock = NSLock()

    func read(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func write(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = value
    }
}
EOF

cat > Tests/LRUCacheTests.swift <<'EOF'
import Testing

@Test("evicts the least recently used entry")
func evictsLeastRecentlyUsed() {
    let cache = LRUCache<String, Int>(capacity: 2)
    cache.insert(1, for: "a")
    cache.insert(2, for: "b")
    _ = cache.value(for: "a")
    cache.insert(3, for: "c")
    #expect(cache.value(for: "b") == nil)
}
EOF

git add -A
git commit -qm "Add LRU cache"

# --- ブランチでの変更（サイドバーでは branchModified、差分表示の題材になる）---
git checkout -q -b feature/eviction-policy

cat > Sources/LRUCache.swift <<'EOF'
import Foundation

/// A simple LRU (Least Recently Used) cache for expensive computations.
final class LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private let policy: EvictionPolicy
    private var storage: [Key: Value] = [:]
    private var usageOrder: [Key] = []
    private(set) var metrics = CacheMetrics()

    init(capacity: Int, policy: EvictionPolicy = .leastRecentlyUsed) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        self.policy = policy
    }

    func value(for key: Key) -> Value? {
        guard let value = storage[key] else {
            metrics.recordMiss()
            return nil
        }
        metrics.recordHit()
        touch(key)
        return value
    }

    func insert(_ value: Value, for key: Key) {
        if storage[key] == nil && storage.count >= capacity {
            evictLeastRecentlyUsed()
        }
        storage[key] = value
        touch(key)
    }

    private func touch(_ key: Key) {
        usageOrder.removeAll { $0 == key }
        usageOrder.append(key)
    }

    private func evictLeastRecentlyUsed() {
        guard let victim = policy.victim(among: usageOrder) else { return }
        usageOrder.removeAll { $0 == victim }
        storage.removeValue(forKey: victim)
    }
}
EOF

cat > Sources/EvictionPolicy.swift <<'EOF'
import Foundation

/// Decides which entry leaves the cache when it is full.
enum EvictionPolicy {
    case leastRecentlyUsed
    case leastFrequentlyUsed

    /// The key that should leave the cache next, or nil when nothing can be evicted.
    func victim<Key>(among usageOrder: [Key]) -> Key? {
        switch self {
        case .leastRecentlyUsed: usageOrder.first
        case .leastFrequentlyUsed: usageOrder.last
        }
    }

    var description: String {
        switch self {
        case .leastRecentlyUsed: "LRU"
        case .leastFrequentlyUsed: "LFU"
        }
    }
}
EOF

git commit -qam "Make the eviction policy pluggable"

# --- unstaged ---
cat > Sources/Metrics.swift <<'EOF'
import Foundation

/// Counts hits and misses so callers can tune the capacity.
struct CacheMetrics {
    private(set) var hits = 0
    private(set) var misses = 0
    private(set) var evictions = 0

    /// Share of lookups that were served from the cache, in the range 0...1.
    var hitRate: Double {
        let total = hits + misses
        return total == 0 ? 0 : Double(hits) / Double(total)
    }

    /// One-line summary for the benchmark output.
    var summary: String {
        let percentage = Int((hitRate * 100).rounded())
        return "\(hits) hits / \(misses) misses (\(percentage)%), \(evictions) evicted"
    }

    /// Resets the counters between benchmark runs.
    mutating func reset() {
        hits = 0
        misses = 0
        evictions = 0
    }

    mutating func recordHit() { hits += 1 }
    mutating func recordMiss() { misses += 1 }
    mutating func recordEviction() { evictions += 1 }
}
EOF

# --- staged ---
cat > Sources/Store.swift <<'EOF'
import Foundation

/// Thread-safe wrapper around the cache storage.
final class Store<Key: Hashable, Value> {
    private var entries: [Key: Value] = [:]
    private let lock = NSLock()

    func read(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func remove(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }

    func write(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = value
    }
}
EOF
git add Sources/Store.swift

# --- untracked ---
cat > Sources/TTLPolicy.swift <<'EOF'
import Foundation

/// Expires entries after a fixed lifetime, independent of usage.
struct TTLPolicy {
    let lifetime: TimeInterval

    func isExpired(insertedAt date: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(date) > lifetime
    }
}
EOF

echo "$target"
