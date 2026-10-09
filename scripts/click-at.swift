// 指定座標をクリックする撮影用の小さな道具(capture-screenshots.applescript から呼ぶ)。
// 使い方: swift scripts/click-at.swift <x> <y> [right|move]
// AX では出せない右クリックのコンテキストメニューを開くために要る。move は動かすだけ
// (撮影前にポインタを窓の外へ退け、ツールチップが写り込まないようにする)。
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
let isMove = a.count > 3 && a[3] == "move"
let isRight = a.count > 3 && a[3] == "right"
let (dn, up, btn): (CGEventType, CGEventType, CGMouseButton) = isRight ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(200000)
if isMove { exit(0) }
CGEvent(mouseEventSource: nil, mouseType: dn, mouseCursorPosition: p, mouseButton: btn)?.post(tap: .cghidEventTap)
usleep(80000)
CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: p, mouseButton: btn)?.post(tap: .cghidEventTap)
