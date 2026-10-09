# Cursor Magnifier（macOS カーソル周辺拡大）

`CursorMagnifier.xcodeproj` を Xcode で開き、Scheme: **CursorMagnifier** / Destination: **My Mac** を選択して **⌘R** で起動してください。

## 操作

- マウスの位置を追跡し、周辺を別ウィンドウに約 12 fps で表示（処理に時間がかかる場合は自動的に低下します）。
- 拡大率スライダー：2〜12倍。画像の中央には黄色い十字を重ねます。
- **一時停止 / 再開**：現在の画像を固定します。
- **最前面に表示**：フローティングウィンドウの切替。
- ディスプレイの端では切り出し範囲を画面内に寄せ、十字位置を補正します。負の座標を含むマルチモニターを考慮しています。

## 画面収録の許可

画面内容を読み取るため、macOS の **画面収録（画面とシステムオーディオの収録）** の許可が必要です。

1. ウィンドウ内の「画面収録の許可 / 再確認」を押す。
2. 求められたら許可する。表示されない場合「システム設定」から「プライバシーとセキュリティ」→「画面収録」を開く。
3. 許可後、**アプリを終了して再起動**する（macOS が再起動を要求する場合があります）。

画面録画ファイルの保存や送信はしません。取得したスクリーンショットはアプリのメモリ上で表示するだけです。アクセシビリティ権限は使用しません。

## 実装・制限

- macOS **15.2 以降** / Apple Silicon 推奨。Swift / AppKit / ScreenCaptureKit（`SCScreenshotManager.captureImage(in:)`）を使用。
- 画面の別ウィンドウ内に拡大画像を表示する仕組みです。OS 全体のズーム機能を変更しません。
- 拡大ウィンドウ自身がカーソルの下にある場合、そのウィンドウも撮影されるため、鏡のような表示になることがあります。避けたい場合は拡大ウィンドウを画面の隅に移動してください。
- アプリ実行を伴う動作確認はユーザーの Mac で行ってください。macOS の Actions ランナーでは画面収録の許可がないため、ビルドと座標のセルフテストのみ検証します。

## Xcode / CLI

プロジェクトはリポジトリ直下の `CursorMagnifier.xcodeproj` にあります。

```bash
xcodebuild -project CursorMagnifier.xcodeproj -scheme CursorMagnifier \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

`--self-test` で座標計算の検証ができます。Xcode はプロジェクトに含まれています。ビルド成果物の .app 自体は GitHub に同梱しません。
