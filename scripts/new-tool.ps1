#Requires -Version 5.1
<#
.SYNOPSIS
    新規ツールを GitHub 上に作成し、submodule として追加、雛形を配置する。

.DESCRIPTION
    1. RemoteUrl 省略時: GitHub CLI (gh) で booyaa-nw/<Name> の空リポジトリを新規作成
       （既に存在するリポジトリを使う場合は -RemoteUrl を指定すればこの手順はスキップされる）
    2. git submodule add で tools/<Name> に追加
    3. src/<pkg_name>/{__init__.py, cli.py} と pyproject.toml を雛形生成
       ([project.scripts] に <Name> を登録、requires-python >= 3.14、hatchling)
    4. scripts/templates/ の .gitattributes / .gitignore をコピー
    5. tools/<Name> 内で git add -A → commit → push
    6. ルートで uv sync
    7. ルートで .gitmodules と tools/<Name> を add → commit

    事前準備: GitHub CLI (https://cli.github.com/) をインストールし、
    `gh auth login` で認証を済ませておいてください。

.PARAMETER Name
    ツール名。tools/<Name> ディレクトリ名、GitHub リポジトリ名、CLI コマンド名として使用します。

.PARAMETER RemoteUrl
    submodule の追加先リモート URL。省略時は https://github.com/booyaa-nw/<Name>.git を使用し、
    gh repo create でそのリポジトリを新規作成します。
    既存のリポジトリを使う場合はこのパラメータを指定してください（その場合、リポジトリの
    自動作成は行われません＝事前に存在している前提になります）。

.PARAMETER Private
    指定すると、新規作成するGitHubリポジトリを Private にします（既定は Public）。
    -RemoteUrl を指定した場合（＝自動作成しない場合）は無視されます。

.EXAMPLE
    ./scripts/new-tool.ps1 -Name ping-checker

.EXAMPLE
    ./scripts/new-tool.ps1 -Name secret-tool -Private

.EXAMPLE
    ./scripts/new-tool.ps1 -Name ip-calc -RemoteUrl git@github.com:booyaa-nw/ip-calc.git
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [string]$RemoteUrl,

    [Parameter(Mandatory = $false)]
    [switch]$Private
)

$ErrorActionPreference = "Stop"

# scripts/ の親 = リポジトリルート
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# RemoteUrl 省略時は booyaa-nw 組織のURLを仮定し、gh repo create で自動作成する
$autoCreateRepo = $false
if (-not $RemoteUrl) {
    $RemoteUrl = "https://github.com/booyaa-nw/$Name.git"
    $autoCreateRepo = $true
}

# Python パッケージ名（ハイフン/空白 -> アンダースコア、小文字化）
$pkgName = ($Name -replace '[-\s]', '_').ToLowerInvariant()
$toolPath = Join-Path "tools" $Name

Write-Host "ツール名     : $Name"
Write-Host "パッケージ名 : $pkgName"
Write-Host "リモートURL  : $RemoteUrl"
Write-Host "配置先       : $toolPath"
Write-Host "自動作成     : $autoCreateRepo$(if ($autoCreateRepo) { " (" + $(if ($Private) { "Private" } else { "Public" }) + ")" })"
Write-Host ""

if (Test-Path $toolPath) {
    Write-Error "'$toolPath' は既に存在します。別の名前を指定するか、既存の内容を確認してください。"
    exit 1
}

# 過去に失敗した試行が残した .git/modules 配下の孤立したgitディレクトリを掃除する。
# （git submodule add は同名のgitディレクトリが .git/modules/<toolPath> に残っていると
#   「A git directory for '<toolPath>' is found locally」で失敗するため）
$staleModuleDir = Join-Path ".git\modules" $toolPath
if (Test-Path $staleModuleDir) {
    Write-Warning "過去の失敗した試行の残骸 ('$staleModuleDir') を検出したため削除します。"
    Remove-Item -Recurse -Force $staleModuleDir
}

# ------------------------------------------------------------
# 1. GitHub上に空リポジトリを作成 (RemoteUrl省略時のみ)
# ------------------------------------------------------------
if ($autoCreateRepo) {
    Write-Step "GitHub上にリポジトリを作成 (gh repo create)"

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI (gh) が見つかりません。https://cli.github.com/ からインストールし、'gh auth login' を実行してから再実行してください。"
        exit 1
    }

    # --add-readme: README付きの初回コミットを作った状態でリポジトリを作成する。
    # 完全に空（コミット0件）のリポジトリだと、この後の git submodule add が
    # チェックアウト対象のコミットが無く失敗する（fatal: You are on a branch yet to be born）ため。
    $visibilityFlag = if ($Private) { "--private" } else { "--public" }
    gh repo create "booyaa-nw/$Name" $visibilityFlag --description "NWエンジニア用ツール: $Name" --add-readme
    if ($LASTEXITCODE -ne 0) {
        Write-Error "gh repo create に失敗しました。'gh auth status' で認証状態を確認するか、'booyaa-nw/$Name' が既に存在していないか確認してください。"
        exit 1
    }
}

# ------------------------------------------------------------
# 2. submodule 追加
# ------------------------------------------------------------
Write-Step "git submodule add"
git submodule add $RemoteUrl $toolPath
if ($LASTEXITCODE -ne 0) {
    Write-Error "git submodule add に失敗しました。GitHub 上にリポジトリ '$RemoteUrl' が存在するか確認してください。"
    exit 1
}

# ------------------------------------------------------------
# 3. 雛形生成
# ------------------------------------------------------------
Write-Step "雛形ファイルの生成"

$srcPkgDir = Join-Path $toolPath "src\$pkgName"
New-Item -ItemType Directory -Path $srcPkgDir -Force | Out-Null

$initPy = @"
"""$Name package."""

__version__ = "0.1.0"
"@
Set-Content -Path (Join-Path $srcPkgDir "__init__.py") -Value $initPy -Encoding utf8

$cliPy = @"
"""$Name CLI エントリポイント."""


def main() -> None:
    print("${Name}: hello from $pkgName")


if __name__ == "__main__":
    main()
"@
Set-Content -Path (Join-Path $srcPkgDir "cli.py") -Value $cliPy -Encoding utf8

$pyprojectContent = @"
[project]
name = "$Name"
version = "0.1.0"
description = ""
requires-python = ">=3.14"
dependencies = []

[project.scripts]
$Name = "$pkgName.cli:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/$pkgName"]
"@
Set-Content -Path (Join-Path $toolPath "pyproject.toml") -Value $pyprojectContent -Encoding utf8

# ------------------------------------------------------------
# 4. 共通テンプレートのコピー
# ------------------------------------------------------------
Write-Step "共通テンプレート (.gitattributes / .gitignore) のコピー"
Copy-Item "scripts/templates/tool.gitattributes" (Join-Path $toolPath ".gitattributes") -Force
Copy-Item "scripts/templates/tool.gitignore" (Join-Path $toolPath ".gitignore") -Force

# ------------------------------------------------------------
# 5. tools/<Name> 内で初回コミット & push
# ------------------------------------------------------------
Write-Step "tools/$Name 内で初回コミット・push"
Push-Location $toolPath
try {
    git add -A
    git commit -m "Initial scaffold for $Name"
    git push
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "push に失敗しました。手動で 'git push' を実行してください（例: リモートの初期ブランチ未設定など）。"
    }
}
finally {
    Pop-Location
}

# ------------------------------------------------------------
# 6. ルートで uv sync --all-packages
# ------------------------------------------------------------
# ルートの pyproject.toml は [tool.uv] package = false かつ dependencies = []
# （ワークスペースをまとめるだけの入れ物）なので、素の `uv sync` では
# 「現在のプロジェクト(ルート)の依存関係」しか同期されず、新規追加した tools/<Name>
# を含むワークスペース全メンバーがインストールされない場合がある。
# ワークスペース全メンバーを確実にインストールするため --all-packages を必ず付ける
# （bootstrap.ps1 と同じ理由。2026-09-12、01_ipcalcチャットでの検証により判明）。
Write-Step "ルートで uv sync --all-packages"
uv sync --all-packages

# ------------------------------------------------------------
# 6b. ./bin のコマンドシムを更新（新しいツールのコマンドを追加）
# ------------------------------------------------------------
Write-Step "./bin のコマンドシムを更新"
& (Join-Path $root "scripts\update-bin.ps1")

# ------------------------------------------------------------
# 7. ルートで .gitmodules と tools/<Name> を commit
# ------------------------------------------------------------
Write-Step "ルートリポジトリで submodule 参照をコミット"
git add ".gitmodules" $toolPath
git commit -m "Add tools/$Name as submodule"

Write-Host ""
Write-Host "完了: tools/$Name を追加しました。" -ForegroundColor Green
Write-Host "  ルートリポジトリの変更を push する場合は 'git push' を実行してください。"
Write-Host ""
