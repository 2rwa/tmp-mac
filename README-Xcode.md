# Xcode で InputMethodStatus をビルドする

1. ZIP を展開し、**InputMethodStatus.xcodeproj** をダブルクリックして Xcode で開く。
2. Scheme が **InputMethodStatus**、実行先が **My Mac** であることを確認。
3. **⌘B** でビルド、**⌘R** で起動。
4. 表示されたウィンドウのテスト欄で日本語／英語入力を切り替え、Input Source ID / Input Mode ID を確認。

macOS 13 以降、Xcode 15 以降を想定。Xcode のプロジェクトから署名は要求しない設定（CODE_SIGNING_ALLOWED=NO）。AppKit / Carbon のシステムフレームワークのみ使用。

## 同梱ファイル
- InputMethodStatus.xcodeproj/ — Xcode プロジェクト（共有 Scheme 同梱）
- input-method/Sources/InputMethodStatus.swift — Swift 全ソース
- input-method/Info.plist — アプリのバンドル定義
- input-method/build.sh — コマンドラインでビルドする場合
- input-method/README.md — 元レポジトリの説明

ビルドで失敗した場合は **Issue Navigator（⌘5）** のエラー全文、Xcode バージョン、macOS バージョンを控えてください。

出典：2rwa/tmp-mac @ 46f556630b857cf9e064aa52e456621cbe82a705 の既存ソースと同一。
