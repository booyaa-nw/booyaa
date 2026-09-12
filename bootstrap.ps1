#Requires -Version 5.1
<#
.SYNOPSIS
    booyaa プロジェクトの初回セットアップ / 再構築スクリプト。

.DESCRIPTION
    1. .python-version が示す Python が uv にインストール済みか確認
    2. .gitmodules があれば git submodule を初期化・更新
    3. uv sync でワークスペース全体の依存関係を同期
    4. ./bin を .venv/Scripts への Junction として作成
    5. 完了メッセージと PATH 追加方法を案内

.EXAMPLE
    ./bootstrap.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# ------------------------------------------------------------
# 1. .python-version の Python が uv にインストール済みか確認
# ------------------------------------------------------------
Write-Step ".python-version の確認"

if (-not (Test-Path ".python-version")) {
    Write-Error ".python-version が見つかりません。リポジトリ直下で実行してください。"
    exit 1
}

$pyVersion = (Get-Content ".python-version" -Raw).Trim()
Write-Host "  要求バージョン: $pyVersion"

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Error "uv コマンドが見つかりません。先に uv をインストールしてください: https://docs.astral.sh/uv/"
    exit 1
}

$installedList = uv python list --only-installed 2>$null
$isInstalled = $installedList | Where-Object { $_ -match [Regex]::Escape($pyVersion) }

if (-not $isInstalled) {
    Write-Warning "Python '$pyVersion' が uv にインストールされていません。"
    Write-Host ""
    Write-Host "  次のコマンドでインストールしてから、再度このスクリプトを実行してください:"
    Write-Host "    uv python install $pyVersion"
    Write-Host ""
    exit 1
}
Write-Host "  OK: インストール済みです。" -ForegroundColor Green

# ------------------------------------------------------------
# 2. submodule の初期化・更新
# ------------------------------------------------------------
if (Test-Path ".gitmodules") {
    Write-Step "git submodule の初期化・更新"
    git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git submodule update に失敗しました。"
        exit 1
    }
}
else {
    Write-Host "(.gitmodules が存在しないため submodule 更新をスキップします)"
}

# ------------------------------------------------------------
# 3. uv sync
# ------------------------------------------------------------
Write-Step "uv sync (ワークスペース全体の依存関係を同期)"
uv sync
if ($LASTEXITCODE -ne 0) {
    Write-Error "uv sync に失敗しました。"
    exit 1
}

# ------------------------------------------------------------
# 4. ./bin -> .venv/Scripts の Junction を作成
# ------------------------------------------------------------
Write-Step "./bin -> .venv/Scripts への Junction を作成"

$binPath = Join-Path $root "bin"
$venvScripts = Join-Path $root ".venv\Scripts"

if (-not (Test-Path $venvScripts)) {
    Write-Error ".venv\Scripts が見つかりません。uv sync が正しく完了しているか確認してください。"
    exit 1
}

if (Test-Path $binPath) {
    $existing = Get-Item $binPath -Force
    if ($existing.LinkType -eq "Junction") {
        Write-Host "  既存の Junction を削除して作り直します。"
        Remove-Item $binPath -Force
    }
    else {
        Write-Error "  '$binPath' は Junction ではない既存のファイル/フォルダです。内容を確認し、手動で削除してから再実行してください。"
        exit 1
    }
}

New-Item -ItemType Junction -Path $binPath -Target $venvScripts | Out-Null
Write-Host "  OK: $binPath -> $venvScripts" -ForegroundColor Green

# ------------------------------------------------------------
# 5. 完了メッセージ
# ------------------------------------------------------------
Write-Step "セットアップ完了"
Write-Host ""
Write-Host "  ./bin を PATH に追加してください（未追加の場合）:"
Write-Host ""
Write-Host "    # 現在の PowerShell セッションのみ有効:"
Write-Host "    `$env:PATH = `"$binPath;`$env:PATH`""
Write-Host ""
Write-Host "    # 恒久的に追加する場合はユーザー環境変数 PATH に以下を追加:"
Write-Host "    $binPath"
Write-Host ""
