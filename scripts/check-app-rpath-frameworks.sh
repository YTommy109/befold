#!/usr/bin/env bash
# .app 内の Mach-O が @rpath/X.framework で要求する framework が、同じ .app の
# Contents/Frameworks に実在することを検査する。
# 同梱 CLI(befold-cli)が BefoldCLI.framework を要求したまま誰も埋め込まず、
# 起動時に dyld で abort した事故の再発防止。ビルドも署名も通るため、実行しない限り気づけない。
# 使い方: scripts/check-app-rpath-frameworks.sh path/to/befold.app
set -euo pipefail
app="${1:?usage: $0 path/to/app}"
bad=0
while IFS= read -r bin; do
  file -b "$bin" | grep -q "Mach-O" || continue
  while IFS= read -r fw; do
    [ -e "$app/Contents/Frameworks/$fw.framework" ] && continue
    echo "NG: $bin が @rpath/$fw.framework を要求するが、Contents/Frameworks に無い" >&2
    bad=1
  done < <(otool -L "$bin" | sed -n 's|.*@rpath/\([^/]*\)\.framework/.*|\1|p' | sort -u)
done < <(find "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/PlugIns" -type f -perm +111 2>/dev/null)
exit $bad
