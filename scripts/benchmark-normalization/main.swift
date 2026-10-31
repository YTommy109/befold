// 単独プロセスで増分正規化を EOF まで進める。ファイル読込と検証用ハッシュは計時外。
import CryptoKit
import Darwin
import Foundation

func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    precondition(status == KERN_SUCCESS)
    return info.resident_size
}

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let started = DispatchTime.now().uptimeNanoseconds
var cache = try NormalizedTextCache(data: data, normalizeFully: false)
while !cache.isFullyNormalized {
    cache.ensureNormalized(minimumLineCount: .max, minimumByteCount: cache.normalizedByteCount + 1)
}

let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
let resident = residentBytes()
var usage = rusage()
precondition(getrusage(RUSAGE_SELF, &usage) == 0)
/// --verify は別プロセスで実行し、全文コピーを性能測定に混ぜない。
var result: [String: Any] = [
    "milliseconds": elapsed, "resident_bytes": resident, "peak_bytes": usage.ru_maxrss,
    "normalized_bytes": cache.normalizedByteCount, "lines": cache.lineCount,
]
if CommandLine.arguments.contains("--verify") {
    result["normalized_sha256"] = SHA256.hash(data: Data(cache.text.utf8))
        .map { String(format: "%02x", $0) }.joined()
}

withExtendedLifetime((data, cache)) {
    let output = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: output, as: UTF8.self))
}
