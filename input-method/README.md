# Input Method Status (macOS)

macOS 標準の Text Input Source Services (Carbon / HIToolbox) を使い、選択中の入力ソースなどを AppKit ウィンドウに表示するネイティブアプリです。追加ライブラリ不要。

## 表示・操作
- 現在選択されている入力ソースの名前、Input Source ID、Input Mode ID、タイプ、言語、各種フラグ
- 現在のキーボードレイアウト、ASCII 対応の入力ソースも区別して表示
- 切り替え通知 + 0.5 秒間隔の確認、手動更新、テキストコピー
- テスト用入力欄を使って日本語／英語切り替えを確認

## ビルド・起動

macOS 13 以降と Xcode Command Line Tools が必要です。

    bash input-method/build.sh
    open dist/InputMethodStatus.app

診断モードと自己テスト：

    dist/InputMethodStatus.app/Contents/MacOS/InputMethodStatus --dump
    dist/InputMethodStatus.app/Contents/MacOS/InputMethodStatus --self-test

## GitHub Actions

[Build Input Method Status](../../actions/workflows/input-method.yml) が `macos-26` の Apple Silicon ランナーでビルドします。ワークフロー成果物 `input-method-status-macos-arm64` は GitHub が作成する外側の ZIP です。一度解凍すると、**`InputMethodStatus-macOS-arm64.dmg`**（推奨）、`InputMethodStatus-macOS-arm64.zip`（アプリ本体を含む内側の ZIP）、診断結果が出てきます。

macOS では **DMG をダブルクリック → 開いたボリュームの `InputMethodStatus.app` を実行**してください（必要なら「アプリケーション」へドラッグ）。ZIP 版を使う場合は内側の ZIP も展開する必要があります。DMG の生成後、CI で実際にマウントし、`InputMethodStatus.app/Contents/MacOS/InputMethodStatus` が実行可能なことを確認します。警告が出る場合は macOS の「プライバシーとセキュリティ」で実行を許可してください。

現在選択中の IME はログインユーザーやアクティブな入力欄で変わります。GitHub-hosted Mac の診断結果は実際の日本語 IME 環境の動作を保証しません。キー入力の中身・変換文字列・候補ウィンドウの内容は収集しません。
