# StreamGrabber

**M3U8ストリーミングビデオダウンローダー**

StreamGrabberは、WebサイトからM3U8形式のストリーミングビデオを検出してダウンロードし、MP4またはMKV形式に自動変換するクロスプラットフォームアプリケーションです。

## 🎯 主な機能

- **自動M3U8検出**: WebサイトURLを入力するだけで、M3U8ストリームを自動検出
- **複数URL対応**: 複数のダウンロードタスクをキューで管理
- **品質選択**: 利用可能な品質から最適なものを選択可能
- **自動ビデオ結合**: TSセグメントを自動的にMP4/MKVに結合
- **進捗表示**: リアルタイムでダウンロード進捗を追跡
- **ライセンス管理**: 30日間のトライアル期間とライセンスキー認証システム
- **クロスプラットフォーム**: Windows、Android対応

## 🚀 使い方

### 1. WebサイトURLを入力
ストリーミングビデオが含まれるWebページのURLを入力します。

### 2. M3U8を自動検出
アプリが自動的にM3U8 URLをスキャンして一覧表示します。

### 3. 品質を選択
複数の品質が利用可能な場合、希望する品質を選択できます。

### 4. ダウンロード開始
ダウンロードキューに追加されると、自動的にダウンロードが開始されます。

### 5. 完了
ダウンロードと結合が完了すると、指定フォルダにMP4/MKVファイルが保存されます。

## 📦 技術スタック

- **Flutter**: クロスプラットフォームUIフレームワーク
- **Dio**: HTTP通信
- **FFmpeg**: ビデオセグメント結合
- **Provider**: 状態管理
- **Sqflite**: ローカルデータベース
- **HTML Parser**: WebページからM3U8 URL検出
- **Shared Preferences**: 設定とライセンス保存

## 🛠️ セットアップ

### 必要要件

- Flutter SDK 3.0以上
- Dart 3.0以上
- Windows: Visual Studio 2022（デスクトップアプリ用）
- Android: Android Studio、Android SDK

### インストール

1. リポジトリをクローン:
```bash
git clone https://github.com/yourusername/stream_grabber.git
cd stream_grabber
```

2. 依存関係をインストール:
```bash
flutter pub get
```

3. アプリを実行:

**Windows版:**
```bash
flutter run -d windows
```

**Android版:**
```bash
flutter run -d android
```

## 🏗️ ビルド

### Windows実行ファイル (.exe)

```bash
flutter build windows --release
```

ビルドされたファイルは `build/windows/runner/Release/` に生成されます。

### Android APK

```bash
flutter build apk --release
```

APKファイルは `build/app/outputs/flutter-apk/app-release.apk` に生成されます。

## 🔑 ライセンス

StreamGrabberは30日間のトライアル期間付きで提供されます。継続利用にはライセンスキーが必要です。

### ライセンスキーの形式
```
SGXX-XXXX-XXXX-XXXX
```

### テストライセンス生成
開発モードでは、設定画面から「テストライセンス生成」ボタンでテストキーを生成できます。

## 📁 プロジェクト構造

```
lib/
├── main.dart                      # アプリケーションエントリーポイント
├── models/                        # データモデル
│   ├── download_task.dart         # ダウンロードタスク
│   └── m3u8_stream.dart          # M3U8ストリーム情報
├── services/                      # ビジネスロジック
│   ├── downloader_service.dart    # ダウンロード処理
│   ├── m3u8_parser.dart          # M3U8解析
│   ├── ffmpeg_service.dart       # ビデオ結合
│   ├── license_service.dart      # ライセンス管理
│   └── database_service.dart     # データベース操作
├── providers/                     # 状態管理
│   └── download_provider.dart    # ダウンロード状態管理
├── screens/                       # UI画面
│   ├── home_screen.dart          # ホーム画面
│   ├── url_input_screen.dart     # URL入力画面
│   └── settings_screen.dart      # 設定画面
└── widgets/                       # 再利用可能ウィジェット
    └── download_item.dart        # ダウンロードアイテム表示
```

## ⚠️ 注意事項

- **著作権**: このアプリは、個人所有のコンテンツまたは合法的に配布されているコンテンツのダウンロードのみに使用してください
- **利用規約**: 各Webサイトの利用規約を遵守してください
- **DRM**: DRMで保護されたコンテンツのダウンロードはサポートしていません

## 💰 収益化

### 販売プラットフォーム

- **Gumroad**: おすすめ（手数料10%）
- **Paddle**: 決済処理代行
- **独自サイト**: 最大利益

### 価格設定

- 買い切り: $19.99 - $29.99
- サブスクリプション: $4.99/月

## 🤝 貢献

プルリクエストは歓迎します！大きな変更を行う場合は、まずissueを開いて変更内容を議論してください。

## 📄 ライセンス

このプロジェクトは独自ライセンスの下でライセンスされています。

## 🔗 リンク

- **公式サイト**: [準備中]
- **購入ページ**: [Gumroad準備中]
- **サポート**: [準備中]

## 📧 お問い合わせ

質問やサポートについては、[準備中] までご連絡ください。

---

**StreamGrabber** - M3U8ストリーミングビデオダウンローダー  
© 2026 StreamGrabber. All rights reserved.
