import Foundation

/// 「表示中テキストが何行か」の数え方の単一情報源。
///
/// バナー("N 行を表示中")の行数は、GUI 本体(ViewerStore)と 1 回描画ホスト
/// (QuickLook 拡張の loadOneShot)の双方が出す。規則が分かれるとホストごとに
/// 表示行数が食い違うため、ここに 1 つだけ置く。
public enum DisplayedLineCount {
    /// content を走査して行数を求める(改行数の増分カウントを持たないホスト向け)。
    public static func count(of content: String) -> Int {
        count(newlines: content.utf8.count { $0 == 0x0A }, in: content)
    }

    /// 既知の改行数から行数を求める(チャンク追記のたびに全走査したくない ViewerStore 向け)。
    /// 末尾が改行で終わらない場合、その途中の行(強制分割チャンク末尾・最終行)も表示中の
    /// 1 行として数える。改行なしの巨大単一行が「0 行」と表示されないようにするため。
    public static func count(newlines: Int, in content: String) -> Int {
        let hasTrailingPartialLine = !content.isEmpty && content.utf8.last != 0x0A
        return newlines + (hasTrailingPartialLine ? 1 : 0)
    }
}
