[English](README.md) | [日本語](README.ja.md)

# osnap

`osnap` は macOS 向けのスクリーンショット CLI です。指定した範囲 — 画面の矩形、
1 つのウィンドウ、特定アプリの全ウィンドウ、メニューバーエクストラのポップアッ
プ — だけを撮影し、それ以外は一切写しません。スクリプトから安全にスクリーン
ショットを撮ることが目的です: 「ボタンだけ撮りたかったのにデスクトップ全部が
写った」「他アプリの中身が漏れた」といった事故を起こさないこと。

メニューバーアプリのドキュメント用に作りました。既存のツールは画面全体を取るか、
自動化できない手作業のクリックを要求するか、のどちらかで困っていました。

## 機能

- `region` / `window` / `app` — 3 種類の狙い撃ちキャプチャ。`screencapture(1)`
  をより安全なデフォルトと整理された出力パスでラップ。
- `menubar-popup` — 起動中アプリのメニューバーエクストラを Accessibility API
  経由で開き、出現したポップアップだけを撮影。
- `popup-wait` — 現在のウィンドウ一覧を記録し、新しいポップアップが出るのを
  待って撮影。手動 or 別ツールでメニューを開く場合に有用。AX 権限不要。
- `list` — 撮影可能なウィンドウを `CGWindowID` / オーナー / レイヤー / 矩形 /
  タイトル付きで列挙。シェルスクリプトと相性◎。

## デモ

`osnap` で撮影したメニューバーポップアップ:

![example popup](docs/example-popup.png)

ポップアップウィンドウだけが映っており、背景のデスクトップ、他アプリ、メニュー
バーの帯は一切含まれていません。対応するコマンド:

```
osascript -e 'tell application "System Events" to tell process "<app>" \
    to click menu bar item 1 of menu bar 2'
ID=$(osnap list --include-menu | awk '/<app>/ {print $1; exit}')
osnap window "$ID" --out popup.png
```

アプリが Accessibility 自動操作に対応している場合:

```
osnap menubar-popup <app> --out popup.png
```

## 必要環境

- macOS 13 以降。
- Swift 5.9 のツールチェイン (Xcode 15+ あるいは独立した Swift toolchain)。
- `osnap` を実行するプロセスに対する Screen Recording 権限 (binary ごとに 1 回。
  System Settings → Privacy & Security → Screen & System Audio Recording)。
- Accessibility 権限は `osnap menubar-popup` のみ必要。System Settings →
  Privacy & Security → Accessibility で binary を追加して有効化。他の
  サブコマンドでは不要。

## インストール

ソースから:

```
git clone https://github.com/Daiki-Iijima/osnap.git
cd osnap
swift build -c release
cp .build/release/osnap /usr/local/bin/                # PATH 上の任意の場所
```

Homebrew formula はまだありません。欲しい場合は issue を立ててください。

## サブコマンド

| コマンド | 撮影対象 | AX 権限 |
|---|---|---|
| `osnap list` | (撮影しない、ウィンドウ一覧を表示) | 不要 |
| `osnap region X,Y,W,H --out f.png` | 画面の矩形 (論理ポイント、左上原点) | 不要 |
| `osnap window <id> --out f.png` | `CGWindowID` 1 つ | 不要 |
| `osnap app <name> --out prefix` | アプリの可視ウィンドウ全部 | 不要 |
| `osnap menubar-popup <app> --out f.png` | アプリのメニューバーポップアップ (自動展開) | 必要 |
| `osnap popup-wait --out f.png` | 次に新規出現したポップアップ | 不要 |

### `list`

```
osnap list                              # 画面上の、メニュー以外のウィンドウ
osnap list --app "Google Chrome"        # オーナー名の部分一致でフィルタ
osnap list --include-menu               # メニュー / ポップアップレイヤーも含める
```

各行: `windowID  layer  owner  title  WxH @ X,Y`。

### `region`

```
osnap region 100,200,800,400 --out region.png
```

引数は X / Y / 幅 / 高さで、いずれも **論理ポイント** (Retina スケーリングは
`screencapture` 側で処理)。左上原点。

### `window`

```
osnap window 1234 --out chrome.png
```

`window` は対象のウィンドウが画面外に部分的にはみ出していても 1 枚にし、丸角
やポップオーバーの形状マスクも保持します。

### `app`

```
osnap app Finder --out finder
# → finder-1.png, finder-2.png, ...
```

`--include-menu` を付けるとアプリのメニューレイヤーウィンドウも対象になります。

### `menubar-popup`

```
osnap menubar-popup MeetingMinutes --out menu.png --settle-ms 250
```

初回実行時に macOS が Accessibility 権限を要求します。許可しない場合は
`popup-wait` に切り替え、メニューは手動 (or 別スクリプト) で開いてください。

内部処理:

1. 名前か bundle ID で起動中アプリを検索。
2. `AXExtrasMenuBar` (または `AXMenuBar`) を読み、各メニューバー項目に対して
   `AXShowMenu` / `AXPress` / `AXOpen` を順に試し、最初に成功したものを採用。
3. `--settle-ms` だけ待ってポップアップの描画完了を待つ。
4. 新規の高レイヤーウィンドウを特定して、それだけを撮影。

SwiftUI の `MenuBarExtra` を使ったアプリで Accessibility アクションが効かない
場合は、AppleScript + `popup-wait` のフォールバックを使ってください:

```
osascript -e 'tell application "System Events" to tell process "<app>" \
    to click menu bar item 1 of menu bar 2'
osnap popup-wait --out menu.png
```

### `popup-wait`

```
osnap popup-wait --out popup.png --timeout 30 --owner MeetingMinutes
```

向いている場面:

- 特定の状態でメニューを手動で開きたい。
- 対象アプリが Accessibility に親和的でない。
- 別ツール (AppleScript / `cliclick` など) からクリックを発火する構成。

`--owner` は新規ウィンドウのオーナー名に対する大小無視の部分一致フィルタ。
`--min-height` は小さなウィンドウ (通知バッジ、ツールチップなど) を除外する
ためのしきい値です。

## 制約

- `osnap` が見えるのは現在のユーザーセッションが見えるウィンドウだけです。
  `kCGWindowSharingNone` 付きで描画されているコンテンツ (パスワード欄の一部、
  DRM 動画、Screen Time でブロック中のアプリ) はキャプチャできません。
- Accessibility の階層はアプリにより異なります。SwiftUI の `MenuBarExtra` は
  `AXExtrasMenuBar` を持ちますが、項目が `AXPress` に応答しないことがあります。
  その場合 `menubar-popup` は失敗するので、AppleScript + `popup-wait` の
  フォールバックを使ってください。
- macOS 26 ではアプリ単位の Screen Recording 権限モデルになっています。OS
  メジャーアップデート後は再付与が必要な場合があります。

## ソースからのビルド

```
swift build -c release
.build/release/osnap --help
```

テストの実行 (現状なし、貢献歓迎):

```
swift test
```

## なぜ別ツール?

- `screencapture -R x,y,w,h` — `region` と同じ考え方。`osnap region` は名前付き
  フラグでラップし、それ以外のキャプチャ (`list` / `app` / `popup-wait` から
  得られる window ID) と組み合わせやすくしています。
- `screencapture -w` (対話的なウィンドウ選択) — 人間のクリックが要るので
  スクリプトには使えません。
- AppleScript 単独 — メニュー項目はクリックできますが、出現したウィンドウのうち
  「今クリックで開いた特定のもの」を `screencapture` に教える術がありません。
  `osnap` がその割り出しを担当します。

## プロジェクト構成

```
Sources/osnap/main.swift       全ソース、1 ファイル
Package.swift                  SwiftPM マニフェスト
Package.resolved               ArgumentParser のピン留め
```

## 状態

v0.1。1.0 未満なので CLI フラグは変わる可能性があります。macOS 26 (Tahoe) で
のみテスト済み。

## ライセンス

MIT。[`LICENSE`](LICENSE) を参照。
