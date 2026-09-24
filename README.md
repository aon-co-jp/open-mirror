# gitlab-mirror

`github.com/aon-co-jp` の全リポジトリを `gitlab.com/aon-co-jp-group` へ**一方向**でミラーするバックアップ用GitHub Actions。

- 実行: 毎日 04:00 JST + 手動実行(Actions → Mirror to GitLab → Run workflow。`only_repos`で対象を絞ったテストも可)
- GitLab側にプロジェクトが無ければ private で自動作成
- 同期対象: ブランチ・タグ(`refs/pull/*`、Git LFS実体、Issue/PR/Wiki/Releasesは対象外)
- GitLab側で直接編集した内容は次回同期で上書きされる(バックアップ専用)

## 設定

| 種類 | 名前 | 内容 |
|---|---|---|
| Secret | `GH_MIRROR_TOKEN` | GitHub fine-grained PAT(All repositories / Contents: Read-only)、期限2027-09 |
| Secret | `GITLAB_TOKEN` | GitLab PAT(api)、期限2027-09-24 |
| Variable | `GITLAB_NAMESPACE_ID` | `143088430` |
| Variable | `GITLAB_NAMESPACE_PATH` | `aon-co-jp-group` |
| Variable(任意) | `EXCLUDE_REPOS` | 除外するリポジトリ名(空白区切り) |

⚠ 両トークンは約1年で失効する。失効前に再発行してSecretsを更新すること。
