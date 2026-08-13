# /menu-audit — メインメニューの実測ダンプ

`MainMenuBuilder` を変更したあと、**実際に走っているアプリのメニュー**を
アクセシビリティ API 経由でダンプし、項目名・ショートカット・有効/無効・
チェック状態を確認する。メニューは自動テスト対象外（`NSMenu` の構築は
`MainMenuBuilderTests` で押さえられるが、`validateMenuItem` の結果は実行時に
しか出ない）ため、ショートカットの割り当てと有効判定はここで実測する。

引数でメニュー名を渡せる（省略時は `View`）: `/menu-audit Edit`

## 手順

### 1. ビルドして起動する

```bash
cd BefoldApp && xcodegen generate && xcodebuild build -scheme befold -destination 'platform=macOS' 2>&1 | tee /tmp/xcb.log | rg "BUILD (SUCCEEDED|FAILED)"
```

**起動するバンドルのパスは必ずビルドログから取る。** `find` で探すと別ワークツリーの
DerivedData を引き、`open -a` は同一バンドル ID の `/Applications/befold.app` へ
吸われる（どちらも古いメニューを観測して誤った結論を出す）。

```bash
APP=$(rg -o "/Users/[^ ]*Build/Products/Debug/befold\.app" /tmp/xcb.log | head -1)
pkill -x befold; sleep 1
mkdir -p .tmp && printf '# menu-audit\n\n本文\n' > .tmp/menu-audit.md
open -a "$APP" "$(git rev-parse --show-toplevel)/.tmp/menu-audit.md"; sleep 6
# 起動したのが意図したバンドルかを確認する
ps -eo pid,args | rg "befold.app/Contents/MacOS/befold" | rg -v rg
```

`/Applications/...` が出たら別バンドルなので、`pkill` して `$APP` を直接指定し直す。

### 2. メニューをダンプする

`enabled` と チェック状態は**メニューを開いた契機で AppKit が検証する**ため、
読む前に必ずメニューバー項目をクリックする（開かずに読むと全項目 `false` に見える）。

```bash
osascript <<'EOF'
tell application "befold" to activate
delay 1
tell application "System Events" to tell process "befold"
  set target to menu bar item "View" of menu bar 1
  click target
  delay 1
  set out to ""
  repeat with mi in menu items of menu 1 of target
    try
      set n to name of mi
      if n is missing value then
        set out to out & "  ----" & linefeed
      else
        set out to out & "  " & n & " [" & (value of attribute "AXMenuItemCmdChar" of mi) & "]" & ¬
          " enabled=" & (enabled of mi) & ¬
          " mark=" & (value of attribute "AXMenuItemMarkChar" of mi) & linefeed
      end if
    end try
  end repeat
  key code 53
  return out
end tell
EOF
```

### 3. ショートカットを実際に叩く

割り当てが効いているかは、キーストロークを送ってチェックの移動を見る
（メニュー項目の存在だけでは、他の項目とキーが衝突していても気付けない）。

```bash
osascript <<'EOF'
tell application "befold" to activate
delay 0.5
tell application "System Events"
  keystroke "3" using command down
  delay 1.5
end tell
EOF
```

このあと 2 を再実行し、チェックが期待どおり移動したかを見る。

### 4. 片付ける

```bash
pkill -x befold; rm -f .tmp/menu-audit.md
```

## 報告

- ダンプ結果をそのまま示し、**期待と一致した項目・しなかった項目**を分けて書く
- 一致しなかった場合、まず「観測しているバイナリが正しいか」（1 の `ps` 出力）を
  疑ってからコードを疑う
- macOS のプライバシー許可ダイアログが出るとモーダルで全メニューが無効化される。
  全項目 `enabled=false` なら、まずスクリーンショットでダイアログの有無を確認する
  （権限を勝手に許可せず、ユーザーに判断を仰ぐか「Don't Allow」で閉じる）
