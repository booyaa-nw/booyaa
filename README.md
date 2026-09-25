# booyaa

ネットワークエンジニア向けのCLIツール群です。
ping・IPアドレス計算・NW機器のコンフィグバックアップなどのツールを1つのディレクトリにまとめ、
共通のPython環境で動かします。

| コマンド | 内容 |
|---|---|
| `mping` | 複数宛先へ同時にpingを実行し、結果をリアルタイム表示・CSVログ出力する |
| `ipcalc` | IPv4 / IPv6 のアドレス・マスクからネットワーク情報を計算する |
| `config_backup` | NW機器（FortiGate / Managed Switch / FortiAnalyzer / Alaxala AX3000）のコンフィグ・システムバックアップ・TAC reportを取得する |

各コマンドの詳しい使い方は `tools/<ツール名>/README.md` を参照してください。

---

## 動作環境

| 項目 | 内容 |
|---|---|
| OS | Windows 10 / 11、Linux（Raspberry Pi などの ARM 機を含む） |
| Python | 3.14 系（推奨: 3.14.7）。uv でインストールするため、システムへの Python インストールは不要です |
| 必要なソフトウェア | Git、uv |
| シェル | Windows: Windows PowerShell 5.1（標準搭載）以降 / Linux: bash（PowerShell は不要） |

---

## インストール手順（Windows）

### 1. Git と uv をインストールする

インストール済みであればこの手順は不要です。PowerShell で次を実行します。

```powershell
# Git
winget install --id Git.Git -e

# uv
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

インストール後、PowerShell を開き直してから `git --version` と `uv --version` が表示されることを確認してください。

### 2. Python をインストールする

```powershell
uv python install 3.14.7
```

### 3. リポジトリを取得する

インストール先は `C:\opt\booyaa` を推奨します（別の場所でも動作します）。

```powershell
mkdir C:\opt -Force
cd C:\opt
git clone --recurse-submodules https://github.com/booyaa-nw/booyaa.git
cd booyaa
```

### 4. セットアップスクリプトを実行する

```powershell
.\bootstrap.ps1
```

スクリプトは次の処理を自動で行います。

1. 必要な Python（3.14 系）が uv にインストールされているか確認
2. 各ツール（git submodule）の取得・更新
3. 依存パッケージのインストール（`uv sync --all-packages`）
4. `bin\windows\` に各コマンドの起動スクリプトを生成

「スクリプトの実行が無効になっている」というエラーで止まる場合は、[トラブルシューティング](#トラブルシューティング) を参照してください。

### 5. PATH を通す

`bin\windows` を PATH に追加します。

**恒久的に追加する（推奨）**

```powershell
[Environment]::SetEnvironmentVariable(
    "Path",
    "C:\opt\booyaa\bin\windows;" + [Environment]::GetEnvironmentVariable("Path", "User"),
    "User"
)
```

実行後、PowerShell を開き直すと反映されます。
（GUI で設定する場合は「システムの詳細設定」→「環境変数」→ ユーザー環境変数の `Path` に `C:\opt\booyaa\bin\windows` を追加）

**今開いている PowerShell だけで試す**

```powershell
$env:PATH = "C:\opt\booyaa\bin\windows;$env:PATH"
```

> コマンドは PowerShell から拡張子なし（`ipcalc` など）で実行できます。コマンドプロンプト（cmd.exe）からは実行できません。

### 6. 動作確認

```powershell
ipcalc 172.16.201.10/24
mping 8.8.8.8
config_backup --help
```

`mping` は `Ctrl+C` で終了します。

---

## インストール手順（Linux）

### 1. Git と uv をインストールする

```bash
# Git（Debian / Ubuntu / Raspberry Pi OS の場合）
sudo apt update && sudo apt install -y git

# uv
curl -LsSf https://astral.sh/uv/install.sh | sh
```

インストール後、シェルを開き直してから `git --version` と `uv --version` が表示されることを確認してください。

### 2. Python をインストールする

```bash
uv python install 3.14.7
```

### 3. リポジトリを取得する

インストール先は任意です（以下は `~/.local/booyaa` の例）。

```bash
cd ~/.local
git clone --recurse-submodules https://github.com/booyaa-nw/booyaa.git
cd booyaa
```

### 4. セットアップスクリプトを実行する

```bash
bash ./bootstrap.sh
```

処理内容は Windows 版と同じで、`bin/linux/` に各コマンドの起動スクリプトが生成されます。

### 5. PATH を通す

`~/.bashrc`（zsh の場合は `~/.zshrc`）に次の1行を追記し、シェルを開き直します。

```bash
export PATH="$HOME/.local/booyaa/bin/linux:$PATH"
```

### 6. 動作確認

```bash
ipcalc 172.16.201.10/24
mping 8.8.8.8
config_backup --help
```

---

## アップデート

新しいバージョンやツールの追加を反映するときは、インストール先で次の3つを実行します。

**Windows**

```powershell
cd C:\opt\booyaa
git pull
git submodule update --init --recursive
.\bootstrap.ps1
```

**Linux**

```bash
cd ~/.local/booyaa
git pull
git submodule update --init --recursive
bash ./bootstrap.sh
```

---

## ログ・出力ファイルの保存先

各ツールは、**コマンドを実行したときのカレントディレクトリ**の下に `booyaa_log/` を作成して結果を保存します
（インストール先ではありません）。

| ツール | 既定の保存先 |
|---|---|
| `mping` | `./booyaa_log/ping/` |
| `config_backup`（FortiGate / FortiAnalyzer / Alaxala） | `./booyaa_log/config/` |
| `config_backup`（Managed Switch） | `./booyaa_log/config/<FortiGateのホスト名>_msw/` |

作業フォルダに移動してから実行すると、結果がその場所にまとまります。保存先は各コマンドのオプションでも変更できます。

---

## トラブルシューティング

### 「このシステムではスクリプトの実行が無効になっているため…」と表示される（Windows）

PowerShell の実行ポリシーで `.ps1` の実行が制限されています。現在のユーザーに対して次を一度だけ実行してください。

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### 「Python '3.14'系が uv にインストールされていません」と表示される

画面の案内どおり Python をインストールしてから、セットアップスクリプトを再実行してください。

```
uv python install 3.14.7
```

### 「uv コマンドが見つかりません」と表示される

uv のインストール後、シェル（PowerShell / ターミナル）を開き直してください。それでも見つからない場合は uv の再インストールを行ってください（https://docs.astral.sh/uv/ ）。

### コマンドが見つからない（`ipcalc` などが実行できない）

- PATH に `bin\windows`（Linux は `bin/linux`）を追加したか、追加後にシェルを開き直したかを確認してください。
- `bin` 配下にファイルが生成されているか確認してください。セットアップ時に「import できません…スキップします」という警告が出ていた場合、そのコマンドは生成されていません。アップデート手順の3コマンドを実行し直してください。

### インストール先のフォルダを移動・名前変更した

`bin` 配下の起動スクリプトにはインストール先のパスが書き込まれています。移動後はセットアップスクリプト（`bootstrap.ps1` / `bootstrap.sh`）を再実行し、PATH の設定も新しい場所に合わせて変更してください。

### `config_backup` のシステムバックアップが失敗する

FortiAnalyzer・Alaxala のシステムバックアップは、機器から実行PCへ FTP でファイルを送らせる方式です。実行中だけ PC 側で一時的な FTP サーバを起動します。

- 待受ポート: FortiAnalyzer は 2121番（`--ftp-port` で変更可）、Alaxala は 21番固定
- 初回実行時に Windows ファイアウォールの許可ダイアログが表示された場合は「許可」を選んでください。
- 機器から実行PCへ上記ポートで通信できる経路が必要です。
- Alaxala の場合、PC 上で他のソフトが 21番ポートを使用中だとシステムバックアップのみ失敗します。

### Linux で `mping` が権限エラーになる

`mping` は root 権限を使わない ICMP ソケットで動作します。OS の設定（`net.ipv4.ping_group_range`）で許可されていない環境では失敗するため、次のいずれかで対応してください。

```bash
# 一時的に許可する（再起動で元に戻る）
sudo sysctl -w net.ipv4.ping_group_range="0 2147483647"
```

または `sudo` を付けて実行してください。

---

## アンインストール

1. PATH から `bin\windows`（Linux は `bin/linux`）を削除します。
2. インストール先のフォルダ（例: `C:\opt\booyaa`）を削除します。

Python 環境（`.venv`）もインストール先フォルダ内にあるため、フォルダの削除だけで完了します。
