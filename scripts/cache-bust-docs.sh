#!/usr/bin/env bash
set -euo pipefail

# docs/style.css / docs/carousel.js がステージされていたら、
# docs/index.html の ?v= キャッシュバスティングハッシュを内容ハッシュで更新する。
# pre-commit フックから呼び出す。

cd "$(git rev-parse --show-toplevel)"

changed=0
for f in docs/style.css docs/carousel.js; do
  if git diff --cached --name-only | grep -qx "$f"; then
    changed=1
  fi
done

if [ "$changed" -eq 0 ]; then
  exit 0
fi

update_hash() {
  local file="$1"
  local base
  base=$(basename "$file")
  local hash
  hash=$(git show ":$file" | shasum -a 256 | cut -c1-8)
  perl -pi -E "s/(\Q${base}\E\?v=)[0-9a-f]+/\${1}${hash}/" docs/index.html
}

update_hash docs/style.css
update_hash docs/carousel.js

git add docs/index.html
echo "pre-commit: docs/index.html のキャッシュバスティングハッシュを更新しました"
