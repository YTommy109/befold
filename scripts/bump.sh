#!/usr/bin/env bash
# バージョン bump & リリースタグ作成スクリプト。
# 使い方: scripts/bump.sh <patch|minor|major|dev> [--dry-run]
#   --dry-run: 変更・コミット・プッシュを行わず、実行内容の表示のみ
set -euo pipefail

err() { echo "エラー: $*" >&2; exit 1; }

# --- 引数の検証 ---
LEVEL="${1:-}"
DRY_RUN=false
[ "${2:-}" = "--dry-run" ] && DRY_RUN=true

case "$LEVEL" in
  patch|minor|major|dev) ;;
  *) err "引数は patch | minor | major | dev のいずれかを指定してください（指定値: '${LEVEL}'）" ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_YML="$ROOT/BefoldApp/project.yml"
[ -f "$PROJECT_YML" ] || err "$PROJECT_YML が見つかりません"

# --- ブランチ・作業ツリーの検証 ---
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || err "main ブランチで実行してください（現在: $BRANCH）"

if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
  err "コミットされていない変更があります。先にコミットまたは退避してください"
fi

# --- バージョンの bump ---
OLD_VERSION="$(sed -n 's/.*MARKETING_VERSION: "\([0-9.]*\)".*/\1/p' "$PROJECT_YML")"
[ -n "$OLD_VERSION" ] || err "MARKETING_VERSION を project.yml から読み取れません"

# --- dev タグの作成（project.yml の変更・コミットは行わない） ---
if [ "$LEVEL" = "dev" ]; then
  # dev は次期 patch のプレリリースとして扱う。SemVer 上 1.4.10-dev.N < 1.4.10 となり、
  # develop チャンネルで正しく更新検知される（現行 stable をベースにすると
  # 1.4.9-dev.N < 1.4.9 となり自分自身より古く扱われ検知されない）
  IFS='.' read -r MAJOR MINOR PATCH <<< "$OLD_VERSION"
  DEV_BASE="${MAJOR}.${MINOR}.$((PATCH + 1))"
  DEV_PREFIX="v${DEV_BASE}-dev."
  LAST_DEV=$(git -C "$ROOT" tag --list "${DEV_PREFIX}*" --sort=-v:refname | head -1)
  if [ -n "$LAST_DEV" ]; then
    LAST_N="${LAST_DEV#"$DEV_PREFIX"}"
    NEW_N=$(( LAST_N + 1 ))
  else
    NEW_N=1
  fi
  DEV_TAG="${DEV_PREFIX}${NEW_N}"
  echo "dev タグ: ${DEV_TAG}"

  if $DRY_RUN; then
    echo "(dry-run のためここで終了します)"
    exit 0
  fi

  git -C "$ROOT" tag "$DEV_TAG"
  git -C "$ROOT" push --tags
  echo "${DEV_TAG} をプッシュしました"
  exit 0
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$OLD_VERSION"
case "$LEVEL" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

git -C "$ROOT" rev-parse -q --verify "refs/tags/v${NEW_VERSION}" >/dev/null \
  && err "タグ v${NEW_VERSION} は既に存在します"

# --- ビルド番号の更新 ---
# +1 は後続の bump コミット自身を数に含めるため。要件は単調増加のみ
OLD_BUILD="$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' "$PROJECT_YML")"
[ -n "$OLD_BUILD" ] || err "CURRENT_PROJECT_VERSION を project.yml から読み取れません"

NEW_BUILD=$(( $(git -C "$ROOT" rev-list --count HEAD) + 1 ))
[ "$NEW_BUILD" -gt "$OLD_BUILD" ] || \
  err "新ビルド番号 ${NEW_BUILD} が現在の ${OLD_BUILD} 以下です"

echo "バージョン:   ${OLD_VERSION} → ${NEW_VERSION}"
echo "ビルド番号:   ${OLD_BUILD} → ${NEW_BUILD}"

if $DRY_RUN; then
  echo "(dry-run のためここで終了します)"
  exit 0
fi

# --- 書き換え・コミット・タグ・プッシュ ---
# BSD sed / GNU sed の -i 非互換を避けるため .bak 方式で書き換える
sed -i.bak \
  -e "s/MARKETING_VERSION: \"${OLD_VERSION}\"/MARKETING_VERSION: \"${NEW_VERSION}\"/" \
  -e "s/CURRENT_PROJECT_VERSION: \"${OLD_BUILD}\"/CURRENT_PROJECT_VERSION: \"${NEW_BUILD}\"/" \
  "$PROJECT_YML"
rm -f "${PROJECT_YML}.bak"

git -C "$ROOT" add "$PROJECT_YML"
git -C "$ROOT" commit -m "chore: バージョンを ${OLD_VERSION} から ${NEW_VERSION} に更新する"
git -C "$ROOT" tag "v${NEW_VERSION}"
git -C "$ROOT" push
git -C "$ROOT" push --tags

echo "v${OLD_VERSION} → v${NEW_VERSION}（ビルド番号 ${NEW_BUILD}）をリリースタグと共にプッシュしました"
