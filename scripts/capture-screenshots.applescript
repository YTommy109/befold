-- scripts/capture-screenshots.applescript
--
-- befold の sample/ 配下のファイルを開き、配布サイト掲載用の
-- スクリーンショットを site/public/images/ に自動生成する。
--
-- 事前準備:
--   1. macOS をダークモードに切り替えておくこと(システム設定 > 外観 > ダーク)。
--      このスクリプトはダークモードの切り替えを行わない。
--   2. スクリーンショット領域(原点 100,100 / 1280x800)が画面に収まる
--      解像度のディスプレイを使用すること。
--   3. 初回実行時、システム設定 > プライバシーとセキュリティ > アクセシビリティ で
--      実行元(ターミナル / スクリプトエディタ)にUI操作の許可を与えること。
--   4. befold.app がインストール済みで、メニュー「Install `befold` command in PATH」
--      により /usr/local/bin/befold が用意されていること。
--   5. 撮影対象領域に他アプリのウィンドウが重ならないようにしておくこと。
--
-- 実行方法:
--   osascript scripts/capture-screenshots.applescript          -- 全部撮り直す
--   osascript scripts/capture-screenshots.applescript 7 8      -- 番号を指定した分だけ撮る
--
-- 番号を指定すると、その screenshot-<番号>.png だけを撮る。既存の画像は撮り直すたびに
-- ピクセルが変わる(アニメーションの位相・アンチエイリアス)ため、1 枚だけ足したいときに
-- 無関係な差分を出さないための指定。
--
-- git のスクリーンショット(差分表示・サイドバーのステータスバッジ)は sample/ では
-- 作れない状態(ブランチでの変更 / staged / unstaged / untracked)を必要とするため、
-- scripts/make-git-demo-repo.sh が組み立てる使い捨てリポジトリを撮る。
--
-- 注意: befold には前回セッション(開いていたタブ)を復元する SessionRestorer が
-- あり、`open -a` で新しいファイルを指定して起動しても前回セッションのタブと
-- 競合してどちらがフォーカスされるか不定になる。このスクリプトは各起動の直前に
-- befold のセッション関連 UserDefaults を削除し、復元対象がない状態で起動する
-- ことでこの競合を回避している。

on run argv

set befoldBundleID to "com.degino.befold"
set scriptPosixPath to POSIX path of (path to me)
set scriptsDir to do shell script "dirname " & quoted form of scriptPosixPath
set repoRoot to do shell script "dirname " & quoted form of scriptsDir
set sampleDir to repoRoot & "/sample"
set imagesDir to repoRoot & "/site/public/images"

set windowX to 100
set windowY to 100
set windowWidth to 1280
set windowHeight to 800
set captureRect to (windowX as string) & "," & (windowY as string) & "," & (windowWidth as string) & "," & (windowHeight as string)

-- 撮影対象のリポジトリ。差分とバッジの状態を毎回同じにするため撮影のたびに作り直す。
set demoRepo to do shell script quoted form of (scriptsDir & "/make-git-demo-repo.sh")

-- 差分のレイアウトはアプリ全体の設定(SourceDiffLayout)なので、キーストロークの
-- トグルでは確定しない。撮影前に左右分割へ固定する。
do shell script "defaults write " & befoldBundleID & " SourceDiffLayout -string side-by-side"

-- CSV の負の数の表記もアプリ全体の設定(CsvNegativeStyle)。既定の plain(-1,234)だと
-- 「負の数の見せ方を選べる」ことが画像から読み取れないため、撮影時だけ ▲+赤字へ固定する。
-- 桁区切り(CsvNumberGrouping)は既定で有効だが、撮影が既定値に依存しないよう明示する。
do shell script "defaults write " & befoldBundleID & " CsvNegativeStyle -string triangleRed"
do shell script "defaults write " & befoldBundleID & " CsvNumberGrouping -bool true"

-- {ファイルのパス, 出力ファイル名, サイドバーを表示するか, Quick Open に打ち込む文字列, 表示モード}
-- パスは "/" 始まりなら絶対パス、そうでなければ sample/ 配下として解決する。
-- 4 番目が "" の場合は Quick Open を開かない。
-- 5 番目は ⌘1〜⌘3 に渡す数字("" ならモードを切り替えない)。表示モードはファイル単位で
-- 永続化されるため、モードを使う対象では毎回明示する。
set targets to {¬
    {"flowchart.mmd", "screenshot-1.png", true, "", ""}, ¬
    {"diagram.svg", "screenshot-2.png", false, "", ""}, ¬
    {"sample.md", "screenshot-3.png", false, "", ""}, ¬
    {"numeric-columns.csv", "screenshot-4.png", false, "", ""}, ¬
    {"example.swift", "screenshot-5.png", false, "", ""}, ¬
    {"sample.md", "screenshot-6.png", false, "samp", ""}, ¬
    {demoRepo & "/Sources/LRUCache.swift", "screenshot-7.png", false, "", "3"}, ¬
    {demoRepo & "/Sources/Metrics.swift", "screenshot-8.png", true, "", "2"}}

-- サイドバーの表示状態を確定させるため CLI 経由で起動する。
set cliPath to "/usr/local/bin/befold"
try
    do shell script "test -x " & quoted form of cliPath
on error
    error "befold CLI が " & cliPath & " に見つからない。befold.app のメニュー " & ¬
        "「Install `befold` command in PATH」でインストールしてから再実行する。"
end try

do shell script "mkdir -p " & quoted form of imagesDir

repeat with targetItem in targets
    set fileName to item 1 of targetItem
    set outputName to item 2 of targetItem
    set showSidebar to item 3 of targetItem
    set quickOpenQuery to item 4 of targetItem
    set displayModeKey to item 5 of targetItem

    if fileName starts with "/" then
        set filePath to fileName
    else
        set filePath to sampleDir & "/" & fileName
    end if
    set outputPath to imagesDir & "/" & outputName

    -- 引数で番号が指定されていれば、その番号の 1 枚だけを撮る。
    set shouldCapture to (count of argv) is 0
    repeat with wantedNumber in argv
        if outputName is "screenshot-" & (wantedNumber as string) & ".png" then set shouldCapture to true
    end repeat

    if shouldCapture then
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

    -- サイドバーの表示状態はファイルごとに永続化されるため、キーストロークの
    -- トグルでは確定しない。CLI の --sidebar / --no-sidebar を override として渡す。
    if showSidebar then
        set sidebarFlag to "--sidebar"
    else
        set sidebarFlag to "--no-sidebar"
    end if
    do shell script quoted form of cliPath & " " & sidebarFlag & " " & quoted form of filePath
    delay 3

    tell application "System Events"
        tell process "befold"
            set position of window 1 to {windowX, windowY}
            set size of window 1 to {windowWidth, windowHeight}
        end tell
    end tell

    -- ウィンドウはファイル毎に保存されたフレームで開くため、ここでのリサイズ後に
    -- WKWebView の再レイアウトが走る。これが終わる前に screencapture すると
    -- 旧レイアウトと新レイアウトが混ざったフレームが撮れるので、長めに待つ。
    delay 3

    tell application "befold" to activate
    delay 2

    if displayModeKey is not "" then
        -- 表示モード(⌘1 レンダリング / ⌘2 ソース / ⌘3 差分)。差分は git を読んでから
        -- 描画するので、描き終わるまで待つ。
        tell application "System Events" to keystroke displayModeKey using {command down}
        delay 3
    end if

    if quickOpenQuery is not "" then
        -- File > Quick Open。パネルは浮動なので描画が落ち着くまで待つ
        tell application "System Events" to keystroke "p" using {command down}
        delay 1
        tell application "System Events" to keystroke quickOpenQuery
        delay 2
    end if

    do shell script "screencapture -x -R" & captureRect & " " & quoted form of outputPath
    end if
end repeat

tell application "befold" to quit

end run
