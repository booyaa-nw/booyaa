#Requires -Version 5.1
<#
.SYNOPSIS
    ./bin 配下に、各ツールのCLIコマンドを呼び出す薄い起動シムを再生成する（Windows/Linux両対応）。

.DESCRIPTION
    tools/*/pyproject.toml の [project.scripts] に登録されたコマンド名とエントリポイント
    (例: ipcalc = "ipcalc.cli:main") を検出し、実行しているOSに応じて次のいずれかにシムを
    生成する。

        bin/windows/<name>.ps1   (Windows)
        bin/linux/<name>.sh      (Linux/Unix、実行権限を付与)

    このプロジェクトでは PyInstaller/Nuitka 等による .exe 化は一切行っていない。また、
    pip/uv が console_scripts から自動生成する launcher(.exe) にも依存しない
    （ワークスペース構成では、そもそも各ツールがその形で venv にインストールされるとは
    限らないため）。シムは、ワークスペース共有venvのpythonインタプリタを
    `-m <モジュール>` で直接起動するだけの薄いラッパーである。

    呼び出し対象モジュール（[project.scripts] の "モジュール:関数" の "モジュール" 部分）は、
    `python -m <モジュール>` で起動できるように `if __name__ == "__main__":` から
    エントリポイント関数を呼び出す作りになっている必要がある（各ツール実装側の規約）。

    開発時（新しいツールを追加した直後）も、ユーザーの初回セットアップ時も、このスクリプト
    (update-bin.ps1) を実行するという同じ手順で対応できる（bootstrap.ps1 / new-tool.ps1 の
    どちらからも呼ばれる）。

    実行OSは自動判定され、そのOSに対応するサブディレクトリ（bin/windows または bin/linux）だけが
    更新される。もう一方のOS用サブディレクトリが（別マシンでの実行結果や共有領域経由で）既に
    存在していても、そちらには触れない。

    【注意】PowerShellの仕様上、PATHに追加していても .ps1 はコマンド名だけでは実行できない
    （.exe/.cmd/.bat と違い、拡張子の自動解決対象に含まれないため）。
    `ipcalc` ではなく `ipcalc.ps1` のように拡張子まで入力する必要がある
    （もしくは各自のPowerShellプロファイルにラッパー関数/エイリアスを定義する）。

.EXAMPLE
    ./scripts/update-bin.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# PowerShell 5.1 (Windows PowerShell Desktop版) には $IsWindows が存在しない。
# Desktop版はWindows専用なので、変数が無ければWindowsとみなす。
$onWindows = $true
if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
    $onWindows = $IsWindows
}

if ($onWindows) {
    $venvPython = Join-Path $root ".venv\Scripts\python.exe"
    $osSubdir = "windows"
    $shimSuffix = ".ps1"
}
else {
    $venvPython = Join-Path $root ".venv/bin/python"
    $osSubdir = "linux"
    $shimSuffix = ".sh"
}

if (-not (Test-Path $venvPython)) {
    Write-Error "$venvPython が見つかりません。先に 'uv sync' を実行してください。"
    exit 1
}

# ------------------------------------------------------------
# 1. tools/*/pyproject.toml の [project.scripts] からコマンド名とモジュールを収集
#    (例: ipcalc = "ipcalc.cli:main" -> name=ipcalc, module=ipcalc.cli)
# ------------------------------------------------------------
Write-Step "各ツールの pyproject.toml から [project.scripts] を収集"

$commands = @{}

Get-ChildItem -Path "tools" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $pyprojectPath = Join-Path $_.FullName "pyproject.toml"
    if (-not (Test-Path $pyprojectPath)) { return }

    $inScriptsSection = $false
    foreach ($line in (Get-Content $pyprojectPath)) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[project\.scripts\]$') {
            $inScriptsSection = $true
            continue
        }
        if ($trimmed -match '^\[.*\]$') {
            $inScriptsSection = $false
            continue
        }
        if ($inScriptsSection -and $trimmed -match '^([A-Za-z0-9_.-]+)\s*=\s*"([^"]+)"') {
            $name = $Matches[1]
            $target = $Matches[2]
            $module = ($target -split ':')[0]
            $commands[$name] = $module
        }
    }
}

if ($commands.Count -eq 0) {
    Write-Warning "登録済みのツールコマンドが見つかりませんでした（tools/ 配下が空、または pyproject.toml が未整備の可能性）。"
}

# ------------------------------------------------------------
# 2. 旧方式（./bin自体がJunction/シンボリックリンク）が残っていれば削除
# ------------------------------------------------------------
$binPath = Join-Path $root "bin"

if (Test-Path $binPath) {
    $binItem = Get-Item $binPath -Force
    if ($binItem.LinkType -eq "Junction" -or $binItem.LinkType -eq "SymbolicLink") {
        Write-Warning "既存の ./bin が旧方式(.venv/Scripts へのJunction/シンボリックリンク)だったため、削除して作り直します。"
        Remove-Item $binPath -Recurse -Force
    }
}

# ------------------------------------------------------------
# 3. 実行中OSに対応する ./bin/<os> を作り直す
# ------------------------------------------------------------
Write-Step "./bin/$osSubdir を再生成 (検出したOS: $osSubdir)"

$osBinPath = Join-Path $binPath $osSubdir
if (Test-Path $osBinPath) {
    Remove-Item $osBinPath -Recurse -Force
}
New-Item -ItemType Directory -Path $osBinPath -Force | Out-Null

# ------------------------------------------------------------
# 4. コマンドごとに、venvのpythonを `-m <モジュール>` で起動する薄いシムを生成
# ------------------------------------------------------------
$generatedCount = 0

foreach ($name in $commands.Keys) {
    $module = $commands[$name]

    # モジュールが実際にimport可能か軽く確認する（タイプミス・未syncの検出のため）。
    # エラー内容は握りつぶさず表示する（原因調査のため）。
    $importError = & $venvPython -c "import importlib; importlib.import_module('$module')" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  '$name' (module: $module) が import できません（'uv sync' 未実施、または実装側の不備の可能性）。スキップします。"
        $importError | ForEach-Object { Write-Warning "    $_" }
        continue
    }

    $shimPath = Join-Path $osBinPath "$name$shimSuffix"

    # 重要: シムは絶対に cd / Set-Location を行わない。呼び出し元のシェルのカレントディレクトリを
    # そのまま子プロセスへ継承させることが目的（ログ出力等でユーザーが今いるディレクトリが
    # 重要になるため）。
    #
    # このプロジェクトではPyInstaller/Nuitka等によるexe化や、pip/uv由来のlauncher(.exe)生成には
    # 依存しない。venv共有のpythonインタプリタを `-m <モジュール>` で直接起動するだけである。
    if ($onWindows) {
        $shimContent = @"
#Requires -Version 5.1
`$ErrorActionPreference = "Stop"
& "$venvPython" -m $module @args
exit `$LASTEXITCODE
"@
        Set-Content -Path $shimPath -Value $shimContent -Encoding utf8 -NoNewline
    }
    else {
        $shimContent = "#!/usr/bin/env bash`nexec `"$venvPython`" -m $module `"`$@`"`n"
        Set-Content -Path $shimPath -Value $shimContent -Encoding utf8 -NoNewline
        & chmod +x $shimPath
    }

    Write-Host "  bin/$osSubdir/$(Split-Path -Leaf $shimPath) -> $venvPython -m $module"
    $generatedCount++
}

# import確認等でpythonを何度も呼んでいるため、ループ内の最後の呼び出しの終了コードが
# $LASTEXITCODE に残ったままになる。ここでリセットしておかないと、import失敗を1件でも
# 警告(スキップ)しただけで、呼び出し元(bootstrap.ps1)が「update-bin.ps1自体が失敗した」と
# 誤判定してしまう。
$LASTEXITCODE = 0

Write-Host ""
Write-Host "完了: ./bin/$osSubdir に $generatedCount / $($commands.Count) 個のコマンドシムを生成しました。" -ForegroundColor Green
Write-Host "  (python / pip / activate 等はここには含まれず、システムのPATHには影響しません)"
if ($onWindows) {
    Write-Host ""
    Write-Host "  [注意] PowerShellの仕様上、.ps1 はコマンド名だけでは実行できません。" -ForegroundColor Yellow
    Write-Host "  'ipcalc' ではなく 'ipcalc.ps1' のように拡張子まで入力してください" -ForegroundColor Yellow
    Write-Host "  (もしくは各自のPowerShellプロファイルにラッパー関数/エイリアスを定義してください)。" -ForegroundColor Yellow
}
Write-Host ""

exit 0
