# HLS Backup Manager

**HLSストリーミング配信管理ツール**

HLS Backup Managerは、著作権者自身が権利を持つHLSストリーミング配信のアーカイブ・品質検査・バックアップを行うための業務用ツールです。M3U8プレイリストからセグメントを取得し、MP4またはMKV形式に自動変換します。

> **本ソフトウェアは著作権者自身の配信管理用途専用です。**  
> DRM保護されたコンテンツには対応していません。

## 主な機能

- **M3U8ストリーム解析**: M3U8 URLを入力し、利用可能なストリーム品質を一覧表示
- **ローカルM3U8ファイル対応**: ローカルに保存されたM3U8ファイルからもアーカイブ可能
- **品質選択**: マスタープレイリストから希望の解像度・ビットレートを選択
- **自動セグメント結合**: TSセグメントをFFmpegでMP4/MKVに自動結合
- **並列処理**: 複数セグメントの同時取得による高速化
- **DRM保護ストリーム拒否**: 暗号化ストリームを検出した場合、処理を自動拒否
- **利用規約同意**: 起動時に利用目的の確認と同意を要求
- **監査ログ**: 入力URL・操作履歴をファイルに自動記録
- **進捗表示**: リアルタイムでアーカイブ進捗を追跡
- **クロスプラットフォーム**: Windows、Android対応

## 使い方

### 1. 初回起動 — 利用規約に同意

初回起動時に表示される利用規約を確認し、同意してください。  
本ツールは著作権者自身の配信管理用途に限定されています。

### 2. M3U8 URLを入力

自分が権利を持つHLSストリームのM3U8 URLを直接入力します。  
または、ローカルに保存されたM3U8ファイルを選択することもできます。

### 3. 品質を選択

マスタープレイリストの場合、利用可能な品質（解像度・ビットレート）から選択できます。  
DRM保護されたストリームは自動的に除外されます。

### 4. アーカイブ開始

キューに追加されると、自動的にセグメントの取得が開始されます。

### 5. 完了

セグメント取得と結合が完了すると、`Documents/HLSBackupManager/Archives/` にMP4/MKVファイルが保存されます。

## 必要要件

- Flutter SDK 3.0以上
- Dart 3.0以上
- **FFmpeg**: セグメント結合に必要（システムPATHに配置）
- Windows: Visual Studio 2022（デスクトップビルド用）
- Android: Android Studio、Android SDK

## セットアップ

### FFmpegのインストール

1. [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) からFFmpegをダウンロード
2. 展開し、`bin` フォルダのパスをシステムの `PATH` 環境変数に追加
3. ターミナルで `ffmpeg -version` が実行できることを確認

### ビルド

```bash
# 依存関係をインストール
flutter pub get

# Windows版を実行
flutter run -d windows

# Windows実行ファイルをビルド
flutter build windows --release

# Android APKをビルド
flutter build apk --release
```

## 技術スタック

- **Flutter** — クロスプラットフォームUIフレームワーク
- **Dio** — HTTP通信
- **FFmpeg** — セグメント結合（外部コマンド）
- **Provider** — 状態管理
- **Sqflite** — ローカルデータベース（タスク管理）
- **Shared Preferences** — 設定・利用規約同意の保存

## プロジェクト構造

```
lib/
├── main.dart                       # エントリーポイント（利用規約同意ゲート含む）
├── models/
│   ├── download_task.dart          # タスクモデル
│   └── m3u8_stream.dart            # M3U8ストリーム情報
├── services/
│   ├── downloader_service.dart     # セグメント取得処理
│   ├── m3u8_parser.dart            # M3U8プレイリスト解析
│   ├── ffmpeg_service.dart         # FFmpegによるセグメント結合
│   ├── audit_log_service.dart      # 監査ログ記録
│   ├── license_service.dart        # ライセンス管理
│   └── database_service.dart       # データベース操作
├── providers/
│   └── download_provider.dart      # タスク状態管理
├── screens/
│   ├── home_screen.dart            # ホーム画面
│   ├── url_input_screen.dart       # M3U8 URL入力画面
│   └── settings_screen.dart        # 設定画面
└── widgets/
    └── download_item.dart          # タスクアイテム表示
```

## 注意事項

- 本ソフトウェアは**著作権者自身の配信管理用途専用**です
- 第三者が権利を持つコンテンツの保存は禁止されています
- DRM保護（Widevine / FairPlay / PlayReady）されたストリームには対応していません
- 暗号鍵の取得・復号処理は一切実装されていません
- すべての操作は監査ログとして自動記録されます

---

**HLS Backup Manager** — HLSストリーミング配信管理ツール  
© 2026 HLS Backup Manager. All rights reserved.
