#Requires -Version 5.1
<#
.SYNOPSIS
    booyaa プロジェクトの初回セットアップ / 再構築スクリプト。

.DESCRIPTION
    1. .python-version が示す Python が uv にインストール済みか確認
    2. .gitmodules があれば git submodule を初期化・更新
    3. uv sync --all-packages でワークスペース全体（全メンバー）の依存関係を同期
    4. scripts/update-bin.ps1 で ./bin/<windows|linux> に各ツールのコマンドシムを生成
       （.venv 配下を丸ごとJunction等で晒すと python/pip/activate等まで
       PATHに乗ってしまうため、コマンド単位の薄い転送シム方式にしている。
       Windows/Linux両対応、実行OSは自動判定される）
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
if ([string]::IsNullOrWhiteSpace($pyVersion)) {
    Write-Error ".python-version の内容が空です。"
    exit 1
}
# .python-version はOS非依存にするため "3.14" のようにマイナーバージョンのみを指定している。
# 実際にインストールする際の推奨パッチバージョンは動作確認済みのこちらを使う。
$recommendedPyVersion = "3.14.7"
Write-Host "  要求バージョン: ${pyVersion}系 (推奨パッチバージョン: $recommendedPyVersion)"

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Error "uv コマンドが見つかりません。先に uv をインストールしてください: https://docs.astral.sh/uv/"
    exit 1
}

$installedList = uv python list --only-installed 2>$null
$isInstalled = $installedList | Where-Object { $_ -match [Regex]::Escape($pyVersion) }

if (-not $isInstalled) {
    Write-Warning "Python '$pyVersion'系が uv にインストールされていません。"
    Write-Host ""
    Write-Host "  次のコマンドでインストールしてから、再度このスクリプトを実行してください:"
    Write-Host "    uv python install $recommendedPyVersion"
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
# 3. uv sync --all-packages
# ------------------------------------------------------------
# ルートの pyproject.toml は [tool.uv] package = false かつ dependencies = []
# （ワークスペースをまとめるだけの入れ物）なので、素の `uv sync` では
# 「現在のプロジェクト(ルート)の依存関係」しか同期されず、tools/* の各メンバー
# (common, ipcalc等) は一切インストールされない。ワークスペース全メンバーを
# 確実にインストールするため --all-packages を必ず付ける。
Write-Step "uv sync --all-packages (ワークスペース全メンバーの依存関係を同期)"
uv sync --all-packages
if ($LASTEXITCODE -ne 0) {
    Write-Error "uv sync --all-packages に失敗しました。"
    exit 1
}

# ------------------------------------------------------------
# 4. ./bin にコマンドシムを生成
# ------------------------------------------------------------
Write-Step "./bin にコマンドシムを生成 (scripts/update-bin.ps1)"
& (Join-Path $root "scripts\update-bin.ps1")
if ($LASTEXITCODE -ne 0) {
    Write-Error "scripts/update-bin.ps1 に失敗しました。"
    exit 1
}

# bin配下のどちらのOSサブディレクトリをPATHに案内するかを判定
# (PowerShell 5.1のDesktop版には$IsWindowsが無い。Desktop版はWindows専用なので、
#  変数が無ければWindowsとみなす)
$onWindows = $true
if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
    $onWindows = $IsWindows
}
$osSubdir = if ($onWindows) { "windows" } else { "linux" }
$binPath = Join-Path (Join-Path $root "bin") $osSubdir

# ------------------------------------------------------------
# 5. 完了メッセージ
# ------------------------------------------------------------
Write-Step "セットアップ完了"
Write-Host ""
Write-Host "  $binPath を PATH に追加してください（未追加の場合）:"
Write-Host ""
if ($onWindows) {
    Write-Host "    # 現在の PowerShell セッションのみ有効:"
    Write-Host "    `$env:PATH = `"$binPath;`$env:PATH`""
    Write-Host ""
    Write-Host "    # 恒久的に追加する場合はユーザー環境変数 PATH に以下を追加:"
    Write-Host "    $binPath"
}
else {
    Write-Host "    # 現在のシェルのみ有効:"
    Write-Host "    export PATH=`"$binPath`:`$PATH`""
    Write-Host ""
    Write-Host "    # 恒久的に追加する場合は ~/.bashrc 等に上記のexport文を追記してください。"
}
Write-Host ""
