#!/bin/bash
# VPS の「厳選バックアップ」。必要最小限だけを集め、2つに分けて作る。
#   (1) 暗号化しない圧縮アーカイブ(秘密も個人情報も含まないものだけ) → GitHub の公開リポジトリ vps-backup へ(最新の1つだけ残す)
#   (2) 秘密または個人情報を含むもの(DBの中身・パスワード類・メール/IP/氏名を含む設定・第三者の文章を含むデータ)は
#       GPG 公開鍵で暗号化 → 手元PCへ別置き
#       (VPS には公開鍵しか無い。復号には手元の秘密鍵が要る。VPS 上には最新2つだけ置く)
#
# 設定ファイル /root/vps-curated-backup.conf(リポジトリには入れない)に次を書く:
#   REPO_URL=https://github.com/<owner>/vps-backup.git   (公開リポジトリ)
#   TOKEN_FILE=/root/.secrets/<github-token-file>   (省略可)
#   FPR_FILE=/root/vps-data-backup.fpr
# 厳選の中身は docs/curation の印(◎/○)に対応する。×・△は含めない。
set -euo pipefail

CONF=${CONF:-/root/vps-curated-backup.conf}
# shellcheck disable=SC1090
source "$CONF"
: "${REPO_URL:?}" "${FPR_FILE:?}"   # TOKEN_FILE は省略可(省略時は git の保存済み認証を使う)
WORKDIR_REPO=${WORKDIR_REPO:-/root/vps-curated-backup-repo}
SECRETS_OUT=${SECRETS_OUT:-/root/vps-secrets-out}
STAMP=$(date +%Y%m%d-%H%M%S)
TOKEN=""; [ -n "${TOKEN_FILE:-}" ] && TOKEN=$(tr -d '\r\n ' < "$TOKEN_FILE")
FPR=$(cat "$FPR_FILE")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PLAIN="$WORK/plain"; SECRET="$WORK/secret"
mkdir -p "$PLAIN/config/nginx" "$PLAIN/config/systemd" "$PLAIN/config/cron" "$PLAIN/db-schema" "$SECRET/db" "$SECRET/config" "$SECRET/files"
hdr() { printf 'AUTHORIZATION: basic %s' "$(printf 'x-access-token:%s' "$TOKEN" | base64 -w0)"; }
gitx() { if [ -n "$TOKEN" ]; then git -c http.extraheader="$(hdr)" "$@"; else git "$@"; fi; }

# 秘密らしい語を含むファイルは暗号化側へ回す(取りこぼすより回しすぎる方を選ぶ)
SECRET_RE='token|secret|passw|api[_-]?key|credential|private[_ -]?key|BEGIN [A-Z ]*PRIVATE'
# 個人情報らしいもの: メールアドレス・氏名・電話番号・IPv4(127.*と0.0.0.0以外)
PII_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}|石塚|ishizuka|[0-9]{2,4}-[0-9]{2,4}-[0-9]{4}'
is_secret() {
  grep -qiE "$SECRET_RE" "$1" 2>/dev/null && return 0
  grep -qE "$PII_RE" "$1" 2>/dev/null && return 0
  grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$1" 2>/dev/null | grep -qvE '^(127\.|0\.0\.0\.0$|255\.)' && return 0
  return 1
}
MANIFEST="$PLAIN/MANIFEST.txt"
{ echo "# vps-curated-backup $STAMP"; echo; } > "$MANIFEST"
note() { echo "$1" >> "$MANIFEST"; }

# ---- 設定(nginx / systemd / cron)。*.bak* は古い退避なので含めない ----
copy_cfg() { # 元ファイル 基準ディレクトリ 平文側 暗号側
  local f="$1" base="$2" pd="$3" sd="$4" rel
  rel="${f#"$base"/}"
  if is_secret "$f"; then mkdir -p "$sd/$(dirname "$rel")"; cp -p "$f" "$sd/$rel"; note "ENCRYPTED  $f"
  else mkdir -p "$pd/$(dirname "$rel")"; cp -p "$f" "$pd/$rel"; note "plain      $f"; fi
}
while IFS= read -r -d '' f; do copy_cfg "$f" /etc/nginx "$PLAIN/config/nginx" "$SECRET/config/nginx"; done \
  < <(find /etc/nginx -type f ! -name '*.bak*' -print0)
while IFS= read -r -d '' f; do copy_cfg "$f" /etc/systemd/system "$PLAIN/config/systemd" "$SECRET/config/systemd"; done \
  < <(find /etc/systemd/system -type f ! -name '*.bak*' -print0)
while IFS= read -r -d '' f; do copy_cfg "$f" /etc/cron.d "$PLAIN/config/cron" "$SECRET/config/cron"; done \
  < <(find /etc/cron.d -type f -print0 2>/dev/null)
crontab -l > "$WORK/crontab.txt" 2>/dev/null || true
if [ -s "$WORK/crontab.txt" ]; then
  if is_secret "$WORK/crontab.txt"; then cp "$WORK/crontab.txt" "$SECRET/config/crontab.txt"; note "ENCRYPTED  crontab -l"
  else cp "$WORK/crontab.txt" "$PLAIN/config/crontab.txt"; note "plain      crontab -l"; fi
fi

# ---- PostgreSQL: 構造だけは平文、中身(ロールのパスワードハッシュ含む)は暗号側 ----
for db in $(sudo -u postgres psql -Atc "select datname from pg_database where not datistemplate and datname<>'postgres'"); do
  sudo -u postgres pg_dump -s "$db" > "$WORK/$db.schema.sql"
  if grep -qE "$PII_RE" "$WORK/$db.schema.sql"; then cp "$WORK/$db.schema.sql" "$SECRET/db/"; note "ENCRYPTED  db schema: $db"
  else cp "$WORK/$db.schema.sql" "$PLAIN/db-schema/"; note "plain      db schema: $db"; fi
  sudo -u postgres pg_dump -Fc "$db" > "$SECRET/db/$db.dump"
  note "ENCRYPTED  db data:   $db"
done
sudo -u postgres pg_dumpall --globals-only > "$SECRET/db/globals.sql"; note "ENCRYPTED  db roles/globals"

# ---- aruaru-db のデータ(中身が分からないので暗号側) ----
if [ -d /root/aruaru-db-data ]; then tar -C /root -cf "$SECRET/files/aruaru-db-data.tar" aruaru-db-data; note "ENCRYPTED  /root/aruaru-db-data"; fi

# ---- 秘密そのもの ----
[ -f /root/aruaru-tokyo.env ] && { cp -p /root/aruaru-tokyo.env "$SECRET/files/"; note "ENCRYPTED  /root/aruaru-tokyo.env"; }
[ -f /root/rs-sync/data/store.json ] && { cp -p /root/rs-sync/data/store.json "$SECRET/files/rs-sync-store.json"; note "ENCRYPTED  /root/rs-sync/data/store.json"; }

# ---- aruaru-llm の学習データ(◎。ニュース等の第三者の文章を含むので公開しない。暗号側。モデル・target は含めない) ----
if [ -d /root/repository/aruaru-llm/data ]; then
  tar -C /root/repository/aruaru-llm -cf "$SECRET/files/aruaru-llm-data.tar" data; note "ENCRYPTED  aruaru-llm/data (third-party text)"
fi

# ---- 中身の目録(平文側。秘密側は件数だけ) ----
( cd "$PLAIN" && find . -type f ! -name MANIFEST.txt -exec sha256sum {} + | sort -k2 ) >> "$MANIFEST"

# ---- (1) 平文の圧縮アーカイブ → GitHub 非公開リポジトリ(最新だけ残す) ----
PLAIN_OUT="vps-curated-$STAMP.tar.zst"
tar -C "$PLAIN" -cf - . | zstd -19 -q -o "$WORK/$PLAIN_OUT"
if [ "${DRY_RUN:-0}" = 1 ]; then  # 試し実行: 公開せず、中身だけ /tmp/vps-curated-dryrun に残す
  rm -rf /tmp/vps-curated-dryrun; mkdir -p /tmp/vps-curated-dryrun; cp -r "$PLAIN"/. /tmp/vps-curated-dryrun/
  echo "DRY_RUN: 平文側の中身を /tmp/vps-curated-dryrun に出しました(push・暗号化はしません)"; exit 0
fi
if [ ! -d "$WORKDIR_REPO/.git" ]; then gitx clone -q "$REPO_URL" "$WORKDIR_REPO"; fi
cd "$WORKDIR_REPO"
gitx pull --rebase -q || true
git config user.name "vps-curated-backup"; git config user.email "noreply@aon.co.jp"
mkdir -p curated
git rm -q --ignore-unmatch curated/vps-curated-*.tar.zst || true
cp "$WORK/$PLAIN_OUT" curated/
cp "$MANIFEST" curated/MANIFEST.txt
cp "$(dirname "$0")/vps-backup-README.md" README.md
git add -A curated README.md
if git diff --cached --quiet; then echo "変更なし"; else
  git commit -q -m "curated backup $STAMP"
  gitx push -q origin HEAD
fi
echo "平文: $PLAIN_OUT ($(du -h "$WORK/$PLAIN_OUT" | cut -f1))"

# ---- (2) 暗号化したアーカイブ(手元へ別置き用。VPS には最新2つだけ) ----
mkdir -p "$SECRETS_OUT"; chmod 700 "$SECRETS_OUT"
SEC_OUT="vps-secrets-$STAMP.tar.zst.gpg"
tar -C "$SECRET" -cf - . | zstd -19 -q | gpg --batch --yes --trust-model always -r "$FPR" -e -o "$SECRETS_OUT/$SEC_OUT"
ls -1t "$SECRETS_OUT"/vps-secrets-*.gpg | tail -n +3 | xargs -r rm -f --
echo "暗号化: $SEC_OUT ($(du -h "$SECRETS_OUT/$SEC_OUT" | cut -f1))"
