import Foundation
import Testing
@testable import mmdview

struct DMGMounterTests {
    @Test
    func extractsMountPointFromHdiutilPlist() throws {
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
              <string>/Volumes/mmdview v1.2.0</string>
            </dict>
          </array>
        </dict>
        </plist>
        """.utf8)
        let mountPoint = DMGMounter.mountPoint(fromPlist: plist)
        #expect(mountPoint?.path == "/Volumes/mmdview v1.2.0")
    }

    @Test
    func returnsNilForPlistWithoutMountPoint() {
        let plist = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict><key>system-entities</key><array/></dict>
        </plist>
        """.utf8)
        #expect(DMGMounter.mountPoint(fromPlist: plist) == nil)
    }

    @Test
    func returnsNilForGarbageData() {
        #expect(DMGMounter.mountPoint(fromPlist: Data("not a plist".utf8)) == nil)
    }
}
