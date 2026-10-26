# open-mirror(旧 gitlab-mirror)

`github.com/aon-co-jp` の**公開**リポジトリ(非公開は対象外)を `gitlab.com/aon-co-jp-group` へ**一方向**でミラーするバックアップ用GitHub Actions。

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
| (自動) | `GITHUB_TOKEN` | Actions標準のトークン。公開リポジトリの読み取りだけに使う(PAT不要)。旧Secret `GH_MIRROR_TOKEN` は不要になったので削除してよい |
| Secret | `GITLAB_TOKEN` | GitLab PAT(api)、期限2027-09-24 |
| Variable | `GITLAB_NAMESPACE_ID` | `143088430` |
| Variable | `GITLAB_NAMESPACE_PATH` | `aon-co-jp-group` |
| Variable(任意) | `EXCLUDE_REPOS` | 除外するリポジトリ名(空白区切り) |
| Variable(任意) | `RELEASE_KEEP` | 添付ファイルを保持する最新リリース数(既定 `make-disk:3`。未記載のリポジトリは全件) |

⚠ `GITLAB_TOKEN` は約1年で失効する。失効前に再発行してSecretsを更新すること。

## 料金について / Billing

このリポジトリは**公開**にしてある。GitHub Actions は公開リポジトリの標準ランナーなら実行時間が無料(非公開リポジトリは月の無料枠を超えると有料)。
GitHub Actions is free for public repositories on standard runners (private repositories are billed beyond the monthly free minutes).
トークンはSecretsに置くため実行ログにも出ない。ただしログ自体は公開される。 / Tokens live in Secrets and are masked in logs, but the logs themselves are public.


## 紹介ページ・デモ(easy-web.tokyo) / Intro page and demo

- 紹介: https://easy-web.tokyo/open-mirror ・ デモ: https://easy-web.tokyo/open-mirror/demo (ブラウザ内だけで動く説明用。架空データ、何も送信しない)
- VPS: `/root/easy-web.tokyo/open-mirror` にclone。`open-mirror-web.service`(ポート8125、`deploy/serve-static.py` で `webpage/` を配信)。`/root/open-web-server/domains.toml` に `path_prefix = "/open-mirror"` を追加済み(変更前は `domains.toml.bak-20261026-openmirror`)。更新は `git pull --ff-only` だけ。
- トップページ(easy-web.tokyo)の紹介は `open-easy-web` の `server/src/main.rs`(`mirror_banner_html`)。

## 状況 / Status

- 稼働中: GitHub の公開リポジトリ → GitLab の毎日のミラー(GitHub Actions、本リポジトリを公開にして無料化)。
- 予定(まだ動かない): バックアップ元=PC・スマホ・タブレット(ネットに繋がったら自動開始)・VPS・レンタルサーバー・GitHub・ブログ、保存先=GitHub・GitLab・ローカルPC・タブレット・スマホ、厳選リスト、圧縮・展開、暗号化・復号。

## VPS の厳選バックアップ(自動) / Curated VPS backup (automatic)

- 公開リポジトリ [`aon-co-jp/vps-backup`](https://github.com/aon-co-jp/vps-backup) に、**秘密情報・個人情報を除いた**最小限(nginx/systemd/cron の設定、DBの構造のみ)を圧縮アーカイブ(`curated/*.tar.zst`、展開は `zstd -dc … | tar -xf -`)で置く。最新の1つだけ残す。
- 秘密または個人情報を含むもの(DBの中身・ロール、パスワード類や秘密語・メール・IP・氏名を含む設定、`.env`、`store.json`、第三者の文章を含む `aruaru-llm/data`)は GPG 公開鍵で暗号化し、VPS の `/root/vps-secrets-out`(最新2つ)から手元 `F:ps-secrets` へ取り寄せる。復号は手元の秘密鍵(`F:ps-data-backup-gpg-PRIVATE.asc`)でのみ可能。
- VPS: `vps-curated-backup.timer`(毎日03:45)→ `deploy/vps-curated-backup.sh`。設定は `/root/vps-curated-backup.conf`(リポジトリには入れない)。
- 手元PC: `deploy/pull-vps-secrets.ps1`。タスク `vps-secrets-pull`(毎日10:00)+ ログオン時(スタートアップの `vps-secrets-pull.cmd`)。ネットに繋がっていなければ次の機会に取り寄せる。
- 復号して中身を見るには手元に `zstd` が要る(`winget install zstd` など)。
- 判定は保守的(秘密語・メール・氏名・電話・127.*以外のIPのどれか1つでも見つかれば暗号側)。除外しすぎる方を選ぶ。
