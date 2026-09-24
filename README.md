# gitlab-mirror

`github.com/aon-co-jp` の全リポジトリを `gitlab.com/aon-co-jp-group` へ**一方向**でミラーするバックアップ用GitHub Actions。

- 実行: 毎日 04:00 JST + 手動実行(Actions → Mirror to GitLab → Run workflow。`only_repos`で対象を絞ったテストも可)
- GitLab側にプロジェクトが無ければ private で自動作成
- 同期対象(GitLab `aon-co-jp-group` 側):
  - コード: ブランチ・タグ・PRのref(`refs/github-pull/*`)
  - Git LFS実体・Wiki(GitHub側に存在するもののみ)
  - Releases: GitLabのReleaseとして再作成。添付ファイルはGeneric Package Registryへ(`make-disk`は最新3リリースだけ保持=約4.3GB、他は全件)
  - Issue・PR・コメント・レビュー・ラベル・マイルストーン・リポジトリ情報: JSONとして`github-metadata-backup`プロジェクトへ(`<リポジトリ名>/*.json`)
- 対象外: Discussions、Projects、Actionsの実行履歴・Secrets、Issue/PR添付画像の実体
- GitLab側で直接編集した内容は次回同期で上書きされる(バックアップ専用)

## 設定

| 種類 | 名前 | 内容 |
|---|---|---|
| Secret | `GH_MIRROR_TOKEN` | GitHub fine-grained PAT(All repositories / Contents・Issues・Pull requests: Read-only)、期限2027-09 |
| Secret | `GITLAB_TOKEN` | GitLab PAT(api)、期限2027-09-24 |
| Variable | `GITLAB_NAMESPACE_ID` | `143088430` |
| Variable | `GITLAB_NAMESPACE_PATH` | `aon-co-jp-group` |
| Variable(任意) | `EXCLUDE_REPOS` | 除外するリポジトリ名(空白区切り) |
| Variable(任意) | `RELEASE_KEEP` | 添付ファイルを保持する最新リリース数(既定 `make-disk:3`。未記載のリポジトリは全件) |

⚠ 両トークンは約1年で失効する。失効前に再発行してSecretsを更新すること。
