@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// `FileWatcher` の catch-up 判定が使う変化検知(TASK-566)。
///
/// 監視開始は非同期になったため、「開始したが、まだ監視していない」区間に起きた変更を
/// 取りこぼす。`FileWatcher.startMonitorsAndCatchUp` は監視開始の前後でこの指紋を撮り、
/// **変わっていたときだけ**通知を出す。無条件に通知すると、走行中の初回読み込みの結果が
/// `loadGeneration` の更新で捨てられ、ファイルを開くたびに読み直しになる。
///
/// つまりこの型が変化を見落とすと取りこぼしになり、変化していないのに違うと言うと
/// 毎回の読み直しになる。両方向をここで固定する。
@Suite
struct FileFingerprintTests {
    @Test("内容が変わると指紋が変わる")
    func detectsContentChange() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD; A-->B")

        let before = FileFingerprint(path: file.path)
        try "graph TD; A-->B-->C".write(to: file, atomically: false, encoding: .utf8)
        let after = FileFingerprint(path: file.path)

        #expect(before != after)
    }

    @Test("変更が無ければ指紋は等しい")
    func staysEqualWithoutChange() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD; A-->B")

        #expect(FileFingerprint(path: file.path) == FileFingerprint(path: file.path))
    }

    @Test("削除は変化として現れる")
    func detectsDeletion() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD; A-->B")

        let before = FileFingerprint(path: file.path)
        try FileManager.default.removeItem(at: file)
        let after = FileFingerprint(path: file.path)

        #expect(before != after)
        #expect(!after.exists)
    }

    /// 同じパスへ別のファイルが入れ替わった場合(アトミック保存・save-by-rename)も
    /// 変化として拾う。サイズと更新時刻が偶然一致しても inode が変わるため。
    @Test("同じ内容でもファイルが差し替わっていれば変化として現れる")
    func detectsReplacementWithIdenticalContent() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let contents = "graph TD; A-->B"
        let file = try tmp.file(named: "a.mmd", contents: contents)

        let before = FileFingerprint(path: file.path)
        let replacement = try tmp.file(named: "b.mmd", contents: contents)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: replacement)
        let after = FileFingerprint(path: file.path)

        #expect(before != after)
    }

    /// 存在しないパスでも「存在しないという指紋」を返す(nil にしない)。
    /// nil にすると「取得できなかった」と「無かった」が同じになり、削除を拾えなくなる。
    @Test("存在しないパスは exists が false の指紋になる")
    func missingPathHasFingerprint() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        let missing = FileFingerprint(path: tmp.url.appendingPathComponent("absent.mmd").path)
        #expect(!missing.exists)
    }
}
