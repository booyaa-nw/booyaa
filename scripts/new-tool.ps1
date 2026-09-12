#Requires -Version 5.1
<#
.SYNOPSIS
    新規ツールを GitHub の空リポジトリから submodule として追加し、雛形を配置する。

.DESCRIPTION
    1. GitHub 上に作成済みの空リポジトリを git submodule add で tools/<Name> に追加
    2. src/<pkg_name>/{__init__.py, cli.py} と pyproject.toml を雛形生成
       ([project.scripts] に <Name> を登録、requires-python >= 3.14、hatchling)
    3. scripts/templates/ の .gitattributes / .gitignore をコピー
    4. tools/<Name> 内で git add -A → commit → push
    5. ルートで uv sync
    6. ルートで .gitmodules と tools/<Name> を add → commit

.PARAMETER Name
    ツール名。tools/<Name> ディレクトリ名、GitHub リポジトリ名、CLI コマンド名として使用します。

.PARAMETER RemoteUrl
    submodule の追加先リモート URL。省略時は https://github.com/booyaa-nw/<Name>.git を使用します。
    （GitHub 側に空リポジトリを事前に作成しておいてください）

.EXAMPLE
    ./scripts/new-tool.ps1 -Name ping-checker

.EXAMPLE
    ./scripts/new-tool.ps1 -Name ip-calc -RemoteUrl git@github.com:booyaa-nw/ip-calc.git
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [string]$RemoteUrl
)

$ErrorActionPreference = "Stop"

# scripts/ の親 = リポジトリルート
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

if (-not $RemoteUrl) {
    $RemoteUrl = "https://github.com/booyaa-nw/$Name.git"
}

# Python パッケージ名（ハイフン/空白 -> アンダースコア、小文字化）
$pkgName = ($Name -replace '[-\s]', '_').ToLowerInvariant()
$toolPath = Join-Path "tools" $Name

Write-Host "ツール名     : $Name"
Write-Host "パッケージ名 : $pkgName"
Write-Host "リモートURL  : $RemoteUrl"
Write-Host "配置先       : $toolPath"
Write-Host ""

if (Test-Path $toolPath) {
    Write-Error "'$toolPath' は既に存在します。別の名前を指定するか、既存の内容を確認してください。"
    exit 1
}

# ------------------------------------------------------------
# 1. submodule 追加
# ------------------------------------------------------------
Write-Step "git submodule add"
git submodule add $RemoteUrl $toolPath
if ($LASTEXITCODE -ne 0) {
    Write-Error "git submodule add に失敗しました。GitHub 上にリポジトリ '$RemoteUrl' が存在するか確認してください。"
    exit 1
}

# ------------------------------------------------------------
# 2. 雛形生成
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
    print("$Name: hello from $pkgName")


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
# 3. 共通テンプレートのコピー
# ------------------------------------------------------------
Write-Step "共通テンプレート (.gitattributes / .gitignore) のコピー"
Copy-Item "scripts/templates/tool.gitattributes" (Join-Path $toolPath ".gitattributes") -Force
Copy-Item "scripts/templates/tool.gitignore" (Join-Path $toolPath ".gitignore") -Force

# ------------------------------------------------------------
# 4. tools/<Name> 内で初回コミット & push
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
# 5. ルートで uv sync
# ------------------------------------------------------------
Write-Step "ルートで uv sync"
uv sync

# ------------------------------------------------------------
# 6. ルートで .gitmodules と tools/<Name> を commit
# ------------------------------------------------------------
Write-Step "ルートリポジトリで submodule 参照をコミット"
git add ".gitmodules" $toolPath
git commit -m "Add tools/$Name as submodule"

Write-Host ""
Write-Host "完了: tools/$Name を追加しました。" -ForegroundColor Green
Write-Host "  ルートリポジトリの変更を push する場合は 'git push' を実行してください。"
Write-Host ""
