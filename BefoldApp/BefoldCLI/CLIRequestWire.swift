import Foundation

/// CLI(送信側)と befold.app(受信側)が共有する Distributed Notification のワイヤ表現。
///
/// 要求の本体は CLIRequest を JSON へエンコードして 1 つのキーに載せる。フィールド単位の
/// 文字列キーを送受で手写しすると、オプションを増やすたびに両側を直す必要があり
/// 取りこぼしが起きるため、表現の責務はこの型と CLIRequest の Codable 適合に閉じている。
///
/// ここには「何を送るか」だけを置く。宛先インスタンスの探索・再送・ACK 待ちは送信側
/// (befold-cli の CLIRequestForwarder)の関心であり、受信側はリンクしない。
public enum CLIRequestWire {
    public static let requestNotificationName = Notification.Name("dev.befold.cli.openRequest")
    public static let ackNotificationName = Notification.Name("dev.befold.cli.openRequestAck")

    /// userInfo のキー。Distributed Notification の userInfo は plist 表現に限られるため、
    /// 要求本体は JSON 文字列として載せる。
    private enum Key {
        static let request = "request"
        static let requestID = "requestID"
    }

    /// 要求を userInfo へエンコードする。エンコードに失敗した場合は nil(送信側は失敗を返す)。
    public static func userInfo(for request: CLIRequest, requestID: String) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(request),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return [Key.request: json, Key.requestID: requestID]
    }

    /// 受信した Distributed Notification の userInfo から要求を復元する。
    public static func decode(userInfo: [AnyHashable: Any]?) -> CLIRequest? {
        guard let json = userInfo?[Key.request] as? String,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CLIRequest.self, from: data)
    }

    /// 受信した Distributed Notification の userInfo から requestID を取り出す(ACK 送信用)。
    public static func requestID(from userInfo: [AnyHashable: Any]?) -> String? {
        userInfo?[Key.requestID] as? String
    }

    /// ACK 通知の userInfo をエンコードする(送信側・テストの双方から参照する単一情報源)。
    public static func ackUserInfo(requestID: String) -> [AnyHashable: Any] {
        [Key.requestID: requestID]
    }

    /// 受信側が要求を受け取ったことを ACK 通知で送り返す。
    public static func sendAck(requestID: String) {
        DistributedNotificationCenter.default().postNotificationName(
            ackNotificationName, object: nil,
            userInfo: ackUserInfo(requestID: requestID), deliverImmediately: true
        )
    }

    /// ACK 通知の userInfo から requestID を取り出す(送信側の待ち受け用)。
    public static func ackRequestID(from userInfo: [AnyHashable: Any]?) -> String? {
        requestID(from: userInfo)
    }
}
