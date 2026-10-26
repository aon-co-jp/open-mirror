#!/bin/bash
# VPS の「厳選バックアップ」。必要最小限だけを集め、2つに分けて作る。
#   (1) 暗号化しない圧縮アーカイブ(秘密を含まないものだけ) → GitHub の非公開リポジトリへ(最新の1つだけ残す)
#   (2) 秘密を含むもの(DBの中身・パスワード類・秘密語を含む設定)は GPG 公開鍵で暗号化 → 手元PCへ別置き
#       (VPS には公開鍵しか無い。復号には手元の秘密鍵が要る。VPS 上には最新2つだけ置く)
#
# 設定ファイル /root/vps-curated-backup.conf(リポジトリには入れない)に次を書く:
#   REPO_URL=https://github.com/<owner>/<private-repo>.git
#   TOKEN_FILE=/root/.secrets/<github-token-file>
#   FPR_FILE=/root/vps-data-backup.fpr
# 厳選の中身は docs/curation の印(◎/○)に対応する。×・△は含めない。
set -euo pipefail

CONF=${CONF:-/root/vps-curated-backup.conf}
# shellcheck disable=SC1090
source "$CONF"
: "${REPO_URL:?}" "${TOKEN_FILE:?}" "${FPR_FILE:?}"
WORKDIR_REPO=${WORKDIR_REPO:-/root/vps-curated-backup-repo}
SECRETS_OUT=${SECRETS_OUT:-/root/vps-secrets-out}
STAMP=$(date +%Y%m%d-%H%M%S)
TOKEN=$(tr -d '\r\n ' < "$TOKEN_FILE")
FPR=$(cat "$FPR_FILE")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PLAIN="$WORK/plain"; SECRET="$WORK/secret"
mkdir -p "$PLAIN/config/nginx" "$PLAIN/config/systemd" "$PLAIN/config/cron" "$PLAIN/db-schema" "$SECRET/db" "$SECRET/config" "$SECRET/files"
hdr() { printf 'AUTHORIZATION: basic %s' "$(printf 'x-access-token:%s' "$TOKEN" | base64 -w0)"; }

# 秘密らしい語を含むファイルは暗号化側へ回す(取りこぼすより回しすぎる方を選ぶ)
SECRET_RE='token|secret|passw|api[_-]?key|credential|private[_ -]?key|BEGIN [A-Z ]*PRIVATE'
is_secret() { grep -qiE "$SECRET_RE" "$1" 2>/dev/null; }
MANIFEST="$PLAIN/MANIFEST.txt"
{ echo "# vps-curated-backup $STAMP"; echo "# host: $(hostname)"; echo; } > "$MANIFEST"
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
  sudo -u postgres pg_dump -s "$db" > "$PLAIN/db-schema/$db.schema.sql"
  sudo -u postgres pg_dump -Fc "$db" > "$SECRET/db/$db.dump"
  note "plain      db schema: $db"; note "ENCRYPTED  db data:   $db"
done
sudo -u postgres pg_dumpall --globals-only > "$SECRET/db/globals.sql"; note "ENCRYPTED  db roles/globals"

# ---- aruaru-db のデータ(中身が分からないので暗号側) ----
if [ -d /root/aruaru-db-data ]; then tar -C /root -cf "$SECRET/files/aruaru-db-data.tar" aruaru-db-data; note "ENCRYPTED  /root/aruaru-db-data"; fi

# ---- 秘密そのもの ----
[ -f /root/aruaru-tokyo.env ] && { cp -p /root/aruaru-tokyo.env "$SECRET/files/"; note "ENCRYPTED  /root/aruaru-tokyo.env"; }
[ -f /root/rs-sync/data/store.json ] && { cp -p /root/rs-sync/data/store.json "$SECRET/files/rs-sync-store.json"; note "ENCRYPTED  /root/rs-sync/data/store.json"; }

# ---- aruaru-llm の学習データ(◎。モデル・target は含めない) ----
if [ -d /root/repository/aruaru-llm/data ]; then
  tar -C /root/repository/aruaru-llm -cf "$PLAIN/aruaru-llm-data.tar" data; note "plain      aruaru-llm/data"
fi

# ---- 中身の目録(平文側。秘密側は件数だけ) ----
( cd "$PLAIN" && find . -type f ! -name MANIFEST.txt -exec sha256sum {} + | sort -k2 ) >> "$MANIFEST"

# ---- (1) 平文の圧縮アーカイブ → GitHub 非公開リポジトリ(最新だけ残す) ----
PLAIN_OUT="vps-curated-$STAMP.tar.zst"
tar -C "$PLAIN" -cf - . | zstd -19 -q -o "$WORK/$PLAIN_OUT"
if [ ! -d "$WORKDIR_REPO/.git" ]; then git -c http.extraheader="$(hdr)" clone -q "$REPO_URL" "$WORKDIR_REPO"; fi
cd "$WORKDIR_REPO"
git -c http.extraheader="$(hdr)" pull --rebase -q || true
git config user.name "vps-curated-backup"; git config user.email "noreply@aon.co.jp"
mkdir -p curated
git rm -q --ignore-unmatch curated/vps-curated-*.tar.zst || true
cp "$WORK/$PLAIN_OUT" curated/
cp "$MANIFEST" curated/MANIFEST.txt
git add -A curated
if git diff --cached --quiet; then echo "変更なし"; else
  git commit -q -m "curated backup $STAMP"
  git -c http.extraheader="$(hdr)" push -q origin HEAD
fi
echo "平文: $PLAIN_OUT ($(du -h "$WORK/$PLAIN_OUT" | cut -f1))"

# ---- (2) 暗号化したアーカイブ(手元へ別置き用。VPS には最新2つだけ) ----
mkdir -p "$SECRETS_OUT"; chmod 700 "$SECRETS_OUT"
SEC_OUT="vps-secrets-$STAMP.tar.zst.gpg"
tar -C "$SECRET" -cf - . | zstd -19 -q | gpg --batch --yes --trust-model always -r "$FPR" -e -o "$SECRETS_OUT/$SEC_OUT"
ls -1t "$SECRETS_OUT"/vps-secrets-*.gpg | tail -n +3 | xargs -r rm -f --
echo "暗号化: $SEC_OUT ($(du -h "$SECRETS_OUT/$SEC_OUT" | cut -f1))"
