#!/usr/bin/env bash
#
# booyaa プロジェクトの初回セットアップ / 再構築スクリプト（Linux/Unix版、bash専用）。
#
# bootstrap.ps1 のbash移植版。Windows PowerShell 5.1 / PowerShell 7 (pwsh) の
# どちらも不要で、bashだけで実行できる（Raspberry Pi等、pwshをインストールしたくない
# Linux/ARM環境向け）。
#
# 処理内容は bootstrap.ps1 と同じ:
#   1. .python-version が示す Python が uv にインストール済みか確認
#   2. .gitmodules があれば git submodule を初期化・更新
#   3. uv sync --all-packages でワークスペース全体（全メンバー）の依存関係を同期
#   4. scripts/update-bin.sh で ./bin/linux に各ツールのコマンドシムを生成
#      （.venv 配下を丸ごと晒すのではなく、コマンド単位の薄い転送シム方式。
#       venv共有のpythonインタプリタを `-m <モジュール>` で直接起動するだけで、
#       PyInstaller/Nuitka等の実行ファイル化やpip/uv由来のlauncher生成には依存しない）
#   5. 完了メッセージと PATH 追加方法を案内
#
# 実行方法（実行権限の有無を気にしなくてよい）:
#   bash ./bootstrap.sh
#
# 直接 ./bootstrap.sh として実行したい場合は、事前に以下で実行権限をgitに記録しておく:
#   chmod +x bootstrap.sh scripts/update-bin.sh
#   git update-index --chmod=+x bootstrap.sh scripts/update-bin.sh
# （bin/ はgit管理外なので、生成されるシム自体の実行権限は毎回このスクリプトが
#   自動で付与する。上記はこのスクリプト自身をgit上で実行可能にしたい場合のみ必要）
#
# 【重要】このファイルは scripts/update-bin.sh と対になっている。Windows側の
# bootstrap.ps1 / scripts/update-bin.ps1 とロジック（要求バージョン確認、
# submodule初期化、`uv sync --all-packages`、bin生成の流れ）を同期させること。
# 一方だけを直すとOS間で挙動がずれる。

set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

step() {
    printf '\033[36m==> %s\033[0m\n' "$1"
}

# ------------------------------------------------------------
# 1. .python-version の Python が uv にインストール済みか確認
# ------------------------------------------------------------
step ".python-version の確認"

if [ ! -f ".python-version" ]; then
    echo "Error: .python-version が見つかりません。リポジトリ直下で実行してください。" >&2
    exit 1
fi

PY_VERSION="$(tr -d '[:space:]' < .python-version)"
if [ -z "$PY_VERSION" ]; then
    echo "Error: .python-version の内容が空です。" >&2
    exit 1
fi

# .python-version はOS非依存にするため "3.14" のようにマイナーバージョンのみを指定している。
# 実際にインストールする際の推奨パッチバージョンは動作確認済みのこちらを使う。
RECOMMENDED_PY_VERSION="3.14.7"
echo "  要求バージョン: ${PY_VERSION}系 (推奨パッチバージョン: ${RECOMMENDED_PY_VERSION})"

if ! command -v uv >/dev/null 2>&1; then
    echo "Error: uv コマンドが見つかりません。先に uv をインストールしてください: https://docs.astral.sh/uv/" >&2
    exit 1
fi

if ! uv python list --only-installed 2>/dev/null | grep -F -q -- "$PY_VERSION"; then
    echo "Warning: Python '${PY_VERSION}'系が uv にインストールされていません。" >&2
    echo ""
    echo "  次のコマンドでインストールしてから、再度このスクリプトを実行してください:"
    echo "    uv python install ${RECOMMENDED_PY_VERSION}"
    echo ""
    exit 1
fi
echo "  OK: インストール済みです。"

# ------------------------------------------------------------
# 2. submodule の初期化・更新
# ------------------------------------------------------------
if [ -f ".gitmodules" ]; then
    step "git submodule の初期化・更新"
    if ! git submodule update --init --recursive; then
        echo "Error: git submodule update に失敗しました。" >&2
        exit 1
    fi
else
    echo "(.gitmodules が存在しないため submodule 更新をスキップします)"
fi

# ------------------------------------------------------------
# 3. uv sync --all-packages
# ------------------------------------------------------------
# ルートの pyproject.toml は [tool.uv] package = false かつ dependencies = []
# （ワークスペースをまとめるだけの入れ物）なので、素の `uv sync` では
# 「現在のプロジェクト(ルート)の依存関係」しか同期されず、tools/* の各メンバー
# (common, ipcalc等) は一切インストールされない場合がある。ワークスペース全メンバーを
# 確実にインストールするため --all-packages を必ず付ける
# （Windows版bootstrap.ps1と同じ理由。2026-09-12判明）。
step "uv sync --all-packages (ワークスペース全メンバーの依存関係を同期)"
if ! uv sync --all-packages; then
    echo "Error: uv sync --all-packages に失敗しました。" >&2
    exit 1
fi

# ------------------------------------------------------------
# 4. ./bin/linux にコマンドシムを生成
# ------------------------------------------------------------
step "./bin/linux にコマンドシムを生成 (scripts/update-bin.sh)"
if ! bash "$ROOT/scripts/update-bin.sh"; then
    echo "Error: scripts/update-bin.sh に失敗しました。" >&2
    exit 1
fi

BIN_PATH="$ROOT/bin/linux"

# ------------------------------------------------------------
# 5. 完了メッセージ
# ------------------------------------------------------------
step "セットアップ完了"
echo ""
echo "  $BIN_PATH を PATH に追加してください（未追加の場合）:"
echo ""
echo "    # 現在のシェルのみ有効:"
echo "    export PATH=\"$BIN_PATH:\$PATH\""
echo ""
echo "    # 恒久的に追加する場合は ~/.bashrc （zshなら ~/.zshrc）に上記のexport文を追記してください。"
echo ""
