# VPS が作った「暗号化済みの秘密アーカイブ」を手元PCへ取り寄せる(別置き用)。
# 復号は手元の秘密鍵(F:\vps-data-backup-gpg-PRIVATE.asc)で行う。VPS には秘密鍵が無い。
#
# 使い方:  powershell -ExecutionPolicy Bypass -File pull-vps-secrets.ps1
#          既定の保存先は F:\vps-secrets (-Dest で変更可)。取り寄せ後、VPS 側の最新2つは残す。
param(
  [string]$Dest = 'F:\vps-secrets',
  [string]$SshHost = 'conoha',
  [string]$RemoteDir = '/root/vps-secrets-out'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$latest = (ssh $SshHost "ls -1t $RemoteDir/vps-secrets-*.gpg | head -n 1").Trim()
if (-not $latest) { throw "VPS に暗号化アーカイブがありません: $RemoteDir" }
$name = Split-Path $latest -Leaf
$target = Join-Path $Dest $name
if (Test-Path $target) { Write-Host "取得済み: $target"; exit 0 }
scp "${SshHost}:$latest" $target
if ($LASTEXITCODE -ne 0) { throw 'scp に失敗しました' }
# 手元にも最新3つだけ残す
Get-ChildItem $Dest -Filter 'vps-secrets-*.gpg' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 | Remove-Item -Force
Write-Host "取得しました: $target ($([math]::Round((Get-Item $target).Length/1KB,1)) KB)"
Write-Host "復号: gpg -d `"$target`" | zstd -d | tar -xf -   (手元の秘密鍵が必要)"
