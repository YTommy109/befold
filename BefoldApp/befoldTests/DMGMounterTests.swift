@testable import befold
import Foundation
import Testing

@Suite
struct DMGMounterTests {
    @Test
    func extractsMountPointFromHdiutilPlist() {
        let plist = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>system-entities</key>
          <array>
            <dict>
              <key>content-hint</key>
              <string>GUID_partition_scheme</string>
            </dict>
            <dict>
              <key>content-hint</key>
              <string>Apple_HFS</string>
              <key>mount-point</key>
              <string>/Volumes/befold v1.2.0</string>
            </dict>
          </array>
        </dict>
        </plist>
        """.utf8)
        let mountPoint = DMGMounter.mountPoint(fromPlist: plist)
        #expect(mountPoint?.path == "/Volumes/befold v1.2.0")
    }

    /// mount-point を含まない plist と plist ですらないデータ、いずれも nil を返す。
    @Test(arguments: [
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict><key>system-entities</key><array/></dict>
        </plist>
        """.utf8),
        Data("not a plist".utf8),
    ])
    func returnsNilForInvalidInput(input: Data) {
        #expect(DMGMounter.mountPoint(fromPlist: input) == nil)
    }
}
