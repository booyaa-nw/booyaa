#!/usr/bin/env bash
#
# ./bin/linux 配下に、各ツールのCLIコマンドを呼び出す薄い起動シムを再生成する
# （Linux/Unix版、bash専用。pwsh不要）。
#
# scripts/update-bin.ps1（Linux分岐部分）のbash移植版。tools/*/pyproject.toml の
# [project.scripts] に登録されたコマンド名とエントリポイント
# (例: ipcalc = "ipcalc.cli:main") を検出し、bin/linux/<name> にシムを生成する。
#
# このプロジェクトでは PyInstaller/Nuitka 等による実行ファイル化は一切行っていない。
# また、pip/uv が console_scripts から自動生成するlauncherにも依存しない
# （ワークスペース構成では、そもそも各ツールがその形で venv にインストールされるとは
# 限らないため）。シムは、ワークスペース共有venvのpythonインタプリタを
# `-m <モジュール>` で直接起動するだけの薄いラッパーである。
#
# 呼び出し対象モジュール（[project.scripts] の "モジュール:関数" の "モジュール" 部分）は、
# `python -m <モジュール>` で起動できるように `if __name__ == "__main__":` から
# エントリポイント関数を呼び出す作りになっている必要がある（各ツール実装側の規約）。
#
# 実行方法:
#   bash scripts/update-bin.sh
# （bootstrap.sh からも呼ばれる。ツール追加後に手動で再実行してもよい）
#
# 【重要】このファイルは bootstrap.sh と対になっており、Windows側の
# scripts/update-bin.ps1 とロジックを同期させること。一方だけを直すとOS間で
# 生成されるシムの挙動がずれる。

set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

step() {
    printf '\033[36m==> %s\033[0m\n' "$1"
}

VENV_PYTHON="$ROOT/.venv/bin/python"

if [ ! -x "$VENV_PYTHON" ]; then
    echo "Error: $VENV_PYTHON が見つかりません。先に 'uv sync --all-packages' を実行してください。" >&2
    exit 1
fi

# ------------------------------------------------------------
# 1. tools/*/pyproject.toml の [project.scripts] からコマンド名とモジュールを収集
#    (例: ipcalc = "ipcalc.cli:main" -> name=ipcalc, module=ipcalc.cli)
# ------------------------------------------------------------
step "各ツールの pyproject.toml から [project.scripts] を収集"

declare -A commands=()

if [ -d "tools" ]; then
    for tool_dir in tools/*/; do
        [ -d "$tool_dir" ] || continue
        pyproject_path="${tool_dir}pyproject.toml"
        [ -f "$pyproject_path" ] || continue

        in_scripts_section=0
        while IFS= read -r line || [ -n "$line" ]; do
            trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            if [ "$trimmed" = "[project.scripts]" ]; then
                in_scripts_section=1
                continue
            fi
            if [[ "$trimmed" =~ ^\[.*\]$ ]]; then
                in_scripts_section=0
                continue
            fi
            if [ "$in_scripts_section" -eq 1 ] && [[ "$trimmed" =~ ^([A-Za-z0-9_.-]+)[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
                name="${BASH_REMATCH[1]}"
                target="${BASH_REMATCH[2]}"
                module="${target%%:*}"
                commands["$name"]="$module"
            fi
        done < "$pyproject_path"
    done
fi

if [ "${#commands[@]}" -eq 0 ]; then
    echo "Warning: 登録済みのツールコマンドが見つかりませんでした（tools/ 配下が空、または pyproject.toml が未整備の可能性）。" >&2
fi

# ------------------------------------------------------------
# 2. 旧方式（./bin自体がシンボリックリンク）が残っていれば削除
# ------------------------------------------------------------
BIN_PATH="$ROOT/bin"

if [ -L "$BIN_PATH" ]; then
    echo "Warning: 既存の ./bin が旧方式(シンボリックリンク)だったため、削除して作り直します。" >&2
    rm -f "$BIN_PATH"
fi

# ------------------------------------------------------------
# 3. ./bin/linux を作り直す
# ------------------------------------------------------------
step "./bin/linux を再生成"

OS_BIN_PATH="$BIN_PATH/linux"
rm -rf "$OS_BIN_PATH"
mkdir -p "$OS_BIN_PATH"

# ------------------------------------------------------------
# 4. コマンドごとに、venvのpythonを `-m <モジュール>` で起動する薄いシムを生成
# ------------------------------------------------------------
generated_count=0
total_count=${#commands[@]}

for name in "${!commands[@]}"; do
    module="${commands[$name]}"

    # モジュールが実際にimport可能か軽く確認する（タイプミス・未syncの検出のため）。
    # エラー内容は握りつぶさず表示する（原因調査のため）。
    if ! import_error="$("$VENV_PYTHON" -c "import importlib; importlib.import_module('$module')" 2>&1)"; then
        echo "Warning:  '$name' (module: $module) が import できません（'uv sync --all-packages' 未実施、または実装側の不備の可能性）。スキップします。" >&2
        printf '%s\n' "$import_error" | sed 's/^/    /' >&2
        continue
    fi

    shim_path="$OS_BIN_PATH/$name"

    # 重要: シムは絶対に cd しない。呼び出し元のシェルのカレントディレクトリを
    # そのまま子プロセスへ継承させることが目的（ログ出力等でユーザーが今いるディレクトリが
    # 重要になるため）。execはプロセスを置き換えるだけでcwdを変えない。
    #
    # このプロジェクトではPyInstaller/Nuitka等による実行ファイル化や、pip/uv由来の
    # launcher生成には依存しない。venv共有のpythonインタプリタを `-m <モジュール>` で
    # 直接起動するだけである。
    {
        printf '#!/usr/bin/env bash\n'
        printf 'exec "%s" -m %s "$@"\n' "$VENV_PYTHON" "$module"
    } > "$shim_path"
    chmod +x "$shim_path"

    echo "  bin/linux/$name -> $VENV_PYTHON -m $module"
    generated_count=$((generated_count + 1))
done

echo ""
echo "完了: ./bin/linux に ${generated_count} / ${total_count} 個のコマンドシムを生成しました。"
echo "  (python / pip / activate 等はここには含まれず、システムのPATHには影響しません)"
echo ""

exit 0
