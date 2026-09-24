#!/usr/bin/env bash
# GitHub (aon-co-jp) → GitLab (aon-co-jp-group) 一方向ミラー
# 必要な環境変数:
#   GH_MIRROR_TOKEN        GitHub fine-grained PAT (Contents: Read-only)
#   GITLAB_TOKEN           GitLab PAT (api)
#   GITLAB_NAMESPACE_ID    例: 143088430
#   GITLAB_NAMESPACE_PATH  例: aon-co-jp-group
# 任意:
#   EXCLUDE_REPOS          除外するリポジトリ名(空白区切り)
#   ONLY_REPOS             指定時はこのリポジトリだけ処理(空白区切り、テスト用)
set -uo pipefail

: "${GH_MIRROR_TOKEN:?}" "${GITLAB_TOKEN:?}" "${GITLAB_NAMESPACE_ID:?}" "${GITLAB_NAMESPACE_PATH:?}"
GH_OWNER="aon-co-jp"
GL_API="https://gitlab.com/api/v4"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

gl() { # gl METHOD PATH [curl args...]
  local m="$1" p="$2"; shift 2
  curl -sS -X "$m" -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$@" "$GL_API$p"
}
urlenc() { jq -rn --arg s "$1" '$s|@uri'; }

# 自分(aon-co-jp)所有の全リポジトリ(public/private/archived含む)
mapfile -t REPOS < <(GH_TOKEN="$GH_MIRROR_TOKEN" gh api --paginate \
  "/user/repos?affiliation=owner&per_page=100" --jq '.[] | "\(.name)\t\(.private)\t\(.description // "")"')

ok=0; skip=0; failed=()
for line in "${REPOS[@]}"; do
  IFS=$'\t' read -r name private desc <<<"$line"
  if [[ -n "${ONLY_REPOS:-}" && " $ONLY_REPOS " != *" $name "* ]]; then continue; fi
  if [[ " ${EXCLUDE_REPOS:-} " == *" $name "* ]]; then echo "::notice::skip $name"; skip=$((skip+1)); continue; fi

  echo "::group::$name"
  pid_path="$(urlenc "$GITLAB_NAMESPACE_PATH/$name")"
  pid="$(gl GET "/projects/$pid_path" | jq -r '.id // empty')"
  if [[ -z "$pid" ]]; then
    echo "GitLabにプロジェクトを作成(private)"
    pid="$(gl POST /projects \
      --data-urlencode "name=$name" --data-urlencode "path=$name" \
      --data-urlencode "namespace_id=$GITLAB_NAMESPACE_ID" \
      --data-urlencode "visibility=private" \
      --data-urlencode "description=[mirror of github.com/$GH_OWNER/$name] $desc" \
      | jq -r '.id // empty')"
    if [[ -z "$pid" ]]; then echo "::error::$name: プロジェクト作成失敗"; failed+=("$name"); echo "::endgroup::"; continue; fi
  fi

  # 一方向ミラーなので、強制pushを拒否する保護ブランチを外す
  for b in $(gl GET "/projects/$pid/protected_branches?per_page=100" | jq -r '.[].name // empty'); do
    gl DELETE "/projects/$pid/protected_branches/$(urlenc "$b")" -o /dev/null
  done

  dir="$WORK/$name.git"
  if git clone --quiet --mirror "https://x-access-token:${GH_MIRROR_TOKEN}@github.com/$GH_OWNER/$name.git" "$dir" 2>&1 \
     && git -C "$dir" push --quiet --prune \
          "https://oauth2:${GITLAB_TOKEN}@gitlab.com/$GITLAB_NAMESPACE_PATH/$name.git" \
          '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' 2>&1; then
    ok=$((ok+1))
  else
    echo "::error::$name: clone/push失敗"; failed+=("$name")
  fi
  rm -rf "$dir"
  echo "::endgroup::"
done

{
  echo "## GitLabミラー結果"
  echo "- 成功: $ok / 除外: $skip / 失敗: ${#failed[@]}"
  for f in "${failed[@]}"; do echo "  - ❌ $f"; done
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

[[ ${#failed[@]} -eq 0 ]]
