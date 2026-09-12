# tools/

各ツールは個別の Git リポジトリとして、GitHub organization `booyaa-nw` 配下に
`tools/<ツール名>` の git submodule として配置されます。

## 新規ツールの追加

```powershell
./scripts/new-tool.ps1 -Name <ツール名>
```

`-RemoteUrl` を省略すると `https://github.com/booyaa-nw/<ツール名>.git` が
GitHub 上に空リポジトリとして事前作成済みであることを前提に submodule 追加します。

## 既存ツール一式を取得する（クローン直後 / 再構築時）

```powershell
git clone <root-repo-url> booyaa
cd booyaa
./bootstrap.ps1
```

`bootstrap.ps1` が `git submodule update --init --recursive`、`uv sync`、
`./bin` junction 作成までまとめて行います。

## 運用方針

- 各ツールの開発・コミットは `tools/<ツール名>` ディレクトリ内で完結させてください。
  ルートリポジトリは `.gitmodules` の参照更新以外を扱いません。
- ツールごとの開発は `tools/<ツール名>` フォルダ単位で Claude Code / VS Code を
  開いてください（マルチルートワークスペースで `tools/*` を個別フォルダとして
  追加する形でも構いません）。git 操作の対象を該当ツールに閉じるためです。
- 依存関係の衝突がどうしても解消できない例外的なツールのみ、ルートの
  `pyproject.toml` の `[tool.uv.workspace] members` から外し、そのツール単体で
  個別の `.venv` を持たせてください（`scripts/templates/tool.gitignore` に
  `.venv/` を含めているのはこのケースのためです）。
