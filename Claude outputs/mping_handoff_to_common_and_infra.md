# mpingからの引き継ぎ資料(common化リクエスト / 環境issue)

作成: 2026-09-13 / 起票元: mpingチャット
対象: 内容によって宛先チャットが異なります。各見出しに宛先を明記しています。

## 背景

`tools/mping`(複数宛先同時ping TUIツール)のリニューアルにあたり、以下の方針で進めてきました。

- 「commonで先に用意 → mpingが使う」ではなく、**mping側で自己完結した形でまず実装・テストを済ませ、その結果を引き継いで移植してもらう**方針(ユーザー確認済み)
- 実装・pytest(34件, Linux/Windows双方)・実機での実ping動作確認まで完了(2026-09-13)
- 詳細設計は Claude Project 内 `operations/tool-registry.md` の mping行、および本チャットで作成した `mping_screen_design.md` を参照

以下、**common化候補4点**(→ commonチャット向け)と、**環境issue1点**(→ 00_環境開発実装チャット向け)をまとめます。

---

## A. 環境issue: pytestの`%TEMP%`パーミッションエラー (00_環境開発実装チャット向け)

### 症状
ユーザー環境(PC: nitro5-skull)で`tools/mping`配下`uv run pytest`を実行したところ、`tmp_path`系フィクスチャを使うテストの大半が以下でエラーになった。

```
PermissionError: [WinError 5] アクセスが拒否されました。: 'C:\Users\hanabi-bro\AppData\Local\Temp\pytest-of-hanabi-bro'
```

pytestが`tmp_path`の保持数上限管理のため`%TEMP%\pytest-of-<user>`配下を`os.scandir`で列挙しようとして権限エラーになっている。mpingのテストコード自体の不具合ではなく、**このPCの`%TEMP%\pytest-of-hanabi-bro`ディレクトリのACL/権限に起因する環境側の問題**と考えられる(原因は未特定。過去に別権限で作成された、アンチウイルス等の影響、等の可能性)。

### mpingでの暫定対応(実施済み)
`tools/mping/pyproject.toml`に以下を追加し、`tmp_path`の基点をリポジトリ配下の`.pytest_tmp/`に固定することで問題を回避した。

```toml
[tool.pytest.ini_options]
addopts = "--basetemp=.pytest_tmp"
```

(`.gitignore`にも`.pytest_tmp/`を追加済み)

### 依頼したいこと
- 他のツール(`common`/`ipcalc`)や今後追加されるツールでも同様の`PermissionError`が発生しうる。各ツールの`pyproject.toml`に同じ`addopts`を個別に足していくのは非効率なので、ワークスペース共通の対策(例: ルートの`pyproject.toml`や共通pytest設定での一括対応、あるいは`%TEMP%\pytest-of-<user>`自体の権限修復手順の案内)を検討いただきたい。
- 可能であればユーザー側でも`C:\Users\hanabi-bro\AppData\Local\Temp\pytest-of-hanabi-bro`の権限状況を一度確認いただくと、根本原因の特定につながるかもしれない。

---

## B. common化リクエスト (commonチャット向け)

いずれも `tools/mping/src/mping/` 配下に、mping固有のコードに依存しない自己完結モジュールとして実装済み。移植時はモジュール名を`common.xxx`に変更し、import元(`tools/mping`側)を差し替えるだけで移行できる想定。

### B-1. `_cli_base.py` → `common.cli` (実装・テスト済み)

CLI引数解析の共通基盤。

```python
class BaseArgumentParser(argparse.ArgumentParser):
    """エラー時にusageだけでなく完全なhelpを表示する"""

def positive_int(value: str) -> int: ...       # 正の整数バリデータ
def non_negative_float(value: str) -> float: ...  # 0以上の実数バリデータ
```

- 依存: `argparse`, `sys` のみ(mping固有コードへの依存なし)
- テスト: `tests/test_cli_base.py` 6件、pytest全pass(Linux開発環境・Windows/Python3.14ユーザー環境の両方で確認済み)
- 移植方法: ファイルをそのまま`common/cli.py`等に配置し、mping側は`from common.cli import ...`に差し替えるのみ

### B-2. `_logging.py` → `common.logging` (実装済み・**未使用/未テスト、要確認**)

アプリケーション動作ログ(ping結果CSVとは別の、エラー・警告等)用の最小限ロガー設定ヘルパー。

```python
def build_logger(
    name: str, *, log_dir: Path | None = None, level: int = logging.INFO, filename: str = "app.log"
) -> logging.Logger: ...
```

- **正直な状況報告**: このモジュールはmping内で実装はしたものの、**mping自身の`cli.py`からは現時点で一度も呼び出していません**(mpingは現状rich画面表示のみで、動作ログの出力自体をまだ必要としていないため)。そのため専用のpytestテストも書けていません。インターフェース(関数シグネチャ)としては妥当と考えていますが、実際の利用シーンでの動作確認が取れていない点はご承知おきください。
- 移植時は、必要であれば呼び出し側(他のツール)での実利用を通じてテストを補っていただくのが良いと思います。

### B-3. `ping/` パッケージ → `common.ping` (Windows実装は実機確認済み、Linux実装は未着手)

```
ping/
├── __init__.py    # OS判定によるディスパッチ、ping_async()
├── base.py        # PingResult, ICMP type定数, IP_STATUS→ICMP変換表
├── windows.py      # ctypes + iphlpapi.dll (IcmpSendEcho) 実装
└── linux.py        # 未実装スタブ (NotImplementedError、icmplibで後日実装予定)
```

主要API:

```python
@dataclass(frozen=True)
class PingResult:
    ok: bool
    rtt: float | None          # 秒。タイムアウト時はNone
    icmp_type: int | None
    icmp_code: int | None
    reply_from: str | None = None  # 実際に応答したホスト(TTL超過時は中継ルータ)
    message: str | None = None

async def ping_async(dst_ip: str, *, ttl: int, timeout: float, data_size: int, df: bool) -> PingResult: ...
```

- Windows実装(`ping/windows.py`): `IcmpCreateFile`/`IcmpSendEcho`/`IcmpCloseHandle`を`ctypes`で呼び出し。全関数に`argtypes`/`restype`を明示宣言(省略するとctypesが戻り値を32bit `c_int`扱いしてしまい、64bit `HANDLE`を暗黙に切り詰める不具合があったため修正済み)。TTL/DF(Don't Fragment)/パケットサイズ指定に対応。
- **IP_STATUS→ICMP type/code変換**: `IcmpSendEcho`はWindows独自の`IP_STATUS`を返すため、RFC792のICMP type/codeへの変換表(`IP_STATUS_TO_ICMP`)を用意。特に`IP_PACKET_TOO_BIG`→`(3, 4)`(Fragmentation Needed)の変換は、旧実装(正規表現によるテキストパース)では検出できなかった箇所で、`--df`/`--size`によるMTU試験機能に直結するため重要。
- 実ICMP応答が無い場合(純粋なタイムアウト、送信自体の失敗)は、ログ上で`type`/`code`列を空にしないための疑似コード`TYPE_NO_REPLY=98`/`TYPE_UNKNOWN_ERROR=99`を用意(RFC792の実在typeと衝突しない値)。
- テスト: `tests/test_ping_base.py`(IP_STATUS変換表、5件)は全pass。`ping/windows.py`自体はLinux開発環境ではpytestを書けない(ctypes+Win32 APIのため)が、**ユーザー環境(Windows 11, nitro5-skull)での実機実行(`mping 8.8.8.8`等)で正常動作を確認済み**(RTT表示・CSVログ出力とも正常)。
- `ping/linux.py`は`icmplib`を使った実装が未着手(ユーザー指示により今回のリニューアル対象外、後日対応予定)。common化する場合はこのスタブごと移植し、Linux対応は移植後に着手する形で問題ないと考えています。

### B-4. `fire_and_forget.py` → `common.fire_and_forget` (要相談・未実装)

当初のリクエストでは、`C:\opt\booyaa_old\booyaa\mping\lib\fire_and_forget.py`(`C:\opt\booyaa_old\booyaa\common\fire_and_forget.py`とバイト単位で同一と確認済み)をそのまま移植する想定でした。

しかし、mpingのデータ構造・並列実行方式の見直しにより、**mping自身は最終的にスレッド+`fire_and_forget`ではなく`asyncio.TaskGroup`ベースの実装を採用したため、mping自体はこのユーティリティを使用しなくなりました**。そのため、mping側で「自己完結した形で実装・テスト」する対象が実質無く、この4点目だけは他の3点と違い**未実装・未テストのままです**。

ご確認いただきたい点: このファイルは元々「他のツールでもping以外の場面でfire-and-forget的な非同期実行が必要になる場合がある」という想定での共通化リクエストだったと理解しています。mpingでの利用実績が無くなった今でも、このファイル単体を(動作実績のある既存コードとして)そのまま`common`に移植する価値があるかどうか、ご判断いただけますでしょうか。必要であれば移植自体は単純な複製作業です。

---

## 動作確認サマリ(2026-09-13時点)

- `uv run pytest`(`tools/mping`, ユーザー環境 Windows / Python 3.14.7): 34件全てpass
- 実機ping動作(`mping 8.8.8.8 1.1.1.1`): 正常動作を確認。表示列(Destination/Source/OK/NG/RTT/History)、CSVログ出力(`<PC名>_<送信元>_<宛先>_log.csv`、ヘッダー1行+`start_time,src,dst,result,rtt,type,code,reply_from`)とも仕様通り
- Windows専用ctypes実装(`ping/windows.py`)は実機確認により、B-3に記載の懸念点(argtypes/restype未宣言によるHANDLE切り詰めの可能性)を修正した版で正常動作を確認済み
