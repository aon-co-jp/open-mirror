# vps-backup

VPS(ConoHa)の**厳選バックアップ**です。本当に必要な最小限だけを、**秘密情報と個人情報を除いて**公開しています。自動生成(毎日)で、**最新の1つだけ**を置きます。
A **curated backup** of a VPS: only what really matters, published **without secrets or personal data**. Auto-generated daily; only the **latest** archive is kept.

## 中身 / What is inside

`curated/vps-curated-<日時>.tar.zst` を展開すると次が入っています。 / Extract `curated/vps-curated-<time>.tar.zst`:

| 場所 / Path | 内容 / Content |
|---|---|
| `config/nginx/` | nginx の設定(秘密・個人情報を含まないファイルだけ) / nginx config (only files without secrets or personal data) |
| `config/systemd/` | systemd のユニット(同上) / systemd units (same rule) |
| `config/cron/` | cron(同上) / cron (same rule) |
| `db-schema/` | PostgreSQL の**構造だけ**(データは含まない) / PostgreSQL **schema only** (no data) |
| `MANIFEST.txt` | 入れたもの・暗号化して別置きにしたものの一覧と、各ファイルの SHA-256 / what was included, what was moved to the encrypted copy, plus SHA-256 |

## 入っていないもの / Not included

- パスワード・トークン・APIキー・秘密鍵を含むファイル、メールアドレス・IPアドレス・氏名を含むファイル、データベースの中身、第三者の文章を含むデータは、**このリポジトリには置きません**。GPG で暗号化して持ち主の手元に別置きしています。
  Files with passwords, tokens, API keys or private keys; files with e-mail addresses, IP addresses or names; database contents; and data containing third-party text are **not stored here**. They are GPG-encrypted and kept separately by the owner.
- 判定は「語・パターンが1つでも見つかったら除外」の保守的な方式です。取りこぼしより、除外しすぎを選びます。 / The filter is conservative: one match is enough to exclude a file.

## 展開 / Extract

```bash
zstd -dc curated/vps-curated-*.tar.zst | tar -xf -
```

作り方は [open-mirror](https://github.com/aon-co-jp/open-mirror) の `deploy/vps-curated-backup.sh`。 / Made by `deploy/vps-curated-backup.sh` in [open-mirror](https://github.com/aon-co-jp/open-mirror).
