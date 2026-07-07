-- scripts/capture-screenshots.applescript
--
-- befold の sample/ 配下のファイルを開き、GitHub Pages 掲載用の
-- スクリーンショットを docs/images/ に自動生成する。
--
-- 事前準備:
--   1. macOS をダークモードに切り替えておくこと(システム設定 > 外観 > ダーク)。
--      このスクリプトはダークモードの切り替えを行わない。
--   2. スクリーンショット領域(原点 100,100 / 1280x800)が画面に収まる
--      解像度のディスプレイを使用すること。
--   3. 初回実行時、システム設定 > プライバシーとセキュリティ > アクセシビリティ で
--      実行元(ターミナル / スクリプトエディタ)にUI操作の許可を与えること。
--   4. befold.app がインストール済みであること。
--   5. 撮影対象領域に他アプリのウィンドウが重ならないようにしておくこと。
--
-- 実行方法:
--   osascript scripts/capture-screenshots.applescript
--
-- 注意: befold には前回セッション(開いていたタブ)を復元する SessionRestorer が
-- あり、`open -a` で新しいファイルを指定して起動しても前回セッションのタブと
-- 競合してどちらがフォーカスされるか不定になる。このスクリプトは各起動の直前に
-- befold のセッション関連 UserDefaults を削除し、復元対象がない状態で起動する
-- ことでこの競合を回避している。

set befoldBundleID to "com.degino.befold"
set scriptPosixPath to POSIX path of (path to me)
set scriptsDir to do shell script "dirname " & quoted form of scriptPosixPath
set repoRoot to do shell script "dirname " & quoted form of scriptsDir
set sampleDir to repoRoot & "/sample"
set imagesDir to repoRoot & "/docs/images"

set windowX to 100
set windowY to 100
set windowWidth to 1280
set windowHeight to 800
set captureRect to (windowX as string) & "," & (windowY as string) & "," & (windowWidth as string) & "," & (windowHeight as string)

-- {ファイル名, 出力ファイル名, サイドバーを表示するか, 末尾までスクロールするか}
-- sample.md は冒頭がMermaid図で占められるため、表・箇条書き・引用など
-- Markdownらしい要素が集まる末尾までスクロールしてから撮影する。
set targets to {¬
    {"flowchart.mmd", "screenshot-1.png", true, false}, ¬
    {"sequence.mmd", "screenshot-2.png", false, false}, ¬
    {"sample.md", "screenshot-3.png", false, true}, ¬
    {"sample.csv", "screenshot-4.png", false, false}, ¬
    {"example.swift", "screenshot-5.png", false, false}}

do shell script "mkdir -p " & quoted form of imagesDir

repeat with targetItem in targets
    set fileName to item 1 of targetItem
    set outputName to item 2 of targetItem
    set showSidebar to item 3 of targetItem
    set scrollToEnd to item 4 of targetItem

    set filePath to sampleDir & "/" & fileName
    set outputPath to imagesDir & "/" & outputName

    -- 前回起動していれば終了してクリーンな状態にする
    tell application "System Events"
        if exists (process "befold") then
            tell application "befold" to quit
            delay 1
        end if
    end tell

    -- SessionRestorer による前回セッション復元と競合しないよう、
    -- 起動直前にセッション関連の UserDefaults を消しておく
    do shell script "defaults delete " & befoldBundleID & " SessionOpenFilePaths > /dev/null 2>&1; " & ¬
        "defaults delete " & befoldBundleID & " SessionLayout > /dev/null 2>&1; " & ¬
        "defaults delete " & befoldBundleID & " SessionActiveFilePath > /dev/null 2>&1; true"

    do shell script "open -a befold " & quoted form of filePath
    delay 2

    tell application "System Events"
        tell process "befold"
            set position of window 1 to {windowX, windowY}
            set size of window 1 to {windowWidth, windowHeight}
        end tell
    end tell
    delay 1

    if showSidebar then
        tell application "System Events" to keystroke "b" using {command down}
        delay 1
    end if

    if scrollToEnd then
        -- End キーがコンテンツ(WKWebView)側に届くよう、まず中央をクリックしてフォーカスを移す
        tell application "System Events" to click at {windowX + (windowWidth / 2), windowY + (windowHeight / 2)}
        delay 0.5
        tell application "System Events" to key code 119 -- End
        delay 1
    end if

    tell application "befold" to activate
    delay 1

    do shell script "screencapture -x -R" & captureRect & " " & quoted form of outputPath
end repeat

tell application "befold" to quit
