# MovieJournal · 鑑賞記録

[简体中文](README.md) · [English](README.en.md) · **日本語** · [한국어](README.ko.md)

観た映画やドラマを、ポスター、評価、短い感想とともに記録します。

MovieJournal は SwiftUI と SwiftData で開発された macOS ネイティブアプリです。macOS 14 以降に対応し、システムフレームワークを使用して、鑑賞記録を Mac 内に保存します。

## 1.2.0 の更新

- 「想看」（観たい）・「在看」（視聴中）・「已看」（鑑賞済み）に対応しました。状態で絞り込み、詳細画面やポスターの右クリックメニューから変更できます。追加時は「観たい」が初期値です。
- 自分の評価、鑑賞日、ドラマのシーズンは任意で、後から入力できます。未評価は 0 点として扱わず、評価順では末尾に表示します。
- 状態を変更しても評価、感想、鑑賞履歴は保持します。「鑑賞済み」にすると日付が空の場合のみ今日を設定し、編集画面で消去できます。
- 既存の記録は内容を保持して「鑑賞済み」に移行します。移行前に Backups/BeforeV3.store を作成します。JSON バックアップはバージョン 2 となり、旧形式の読み込みにも対応します。

## 1.1.1 の更新

- 詳細画面の「记录重看」（再鑑賞を記録）から、鑑賞ごとの日付、評価、感想、シーズンを保存できます。ライブラリには直近の鑑賞情報を表示します。
- 「…」メニューで並べ替えとバックアップ・復元ができます。JSON に作品情報、鑑賞履歴、キャッシュ済みポスターを保存し、復元前に追加件数を確認できます。重複作品はローカルの内容を保持します。
- 入力済みの下書きを保護し、保存ボタンを下部に固定しました。監督から作品を探せるほか、ライブラリではタイトル、監督、クリエイター、出演者で検索できます。
- 設定でガラス効果のオフ・クリア・標準と着色の強さを選べます。macOS 26 以降では Liquid Glass、旧 OS では代替マテリアルを使用し、透明度を下げる設定に対応します。
- V1 から V2 へ移行する前に、ライブラリの Backups/BeforeV2.store にデータベースのスナップショットを保存します。

## 機能

- **ポスターライブラリ** — 追加日、鑑賞日、自分の評価で並べ替えられます。タイトル、監督、クリエイター、出演者で検索し、映画・ドラマを絞り込めます。
- **オンライン検索** — TMDB で作品を選ぶと、タイトル、公開年、ジャンル、監督またはクリエイター、主要キャスト5名、あらすじ、ポスター、TMDB 評価を取得します。
- **自分の鑑賞記録** — 鑑賞状態を管理し、日付、1〜10 の整数による評価、感想、シーズンを任意で保存できます。
- **追加の評価情報** — 任意の OMDb API キーを設定すると、作品の追加時に IMDb と Rotten Tomatoes の評価を取得できます。
- **オフラインでの閲覧・編集** — 保存済みの作品情報とダウンロード済みのポスターを閲覧し、自分の鑑賞情報を編集できます。
- **重複チェックと削除確認** — 同じ作品を追加した場合は既存の記録を開けます。削除時には確認を行い、残っている記録の参照に基づいてポスターを整理します。
- **キーチェーンへの保存** — 設定画面から API キーの保存、検証、変更、削除ができます。

## はじめに

1. リポジトリをクローンし、Xcode でプロジェクトを開きます。

   ```sh
   git clone https://github.com/pengde-dede/MovieJournal.git
   cd MovieJournal
   open MovieJournal.xcodeproj
   ```

2. 本バージョンは Xcode 27.2 でビルドを検証し、macOS 14 以降を対象としています。コンパイルには Liquid Glass API を含む macOS SDK が必要です。
3. **Signing & Capabilities** で **Automatically manage signing** を有効にし、アプリとテストの両ターゲットで自分の開発チームを選びます。
4. scheme を **MovieJournal**、実行先を **My Mac** にして、**⌘R** で起動します。
5. **⌘,** で設定を開き、**TMDB API Key（v3）** を入力・保存して **验证**（検証）をクリックします。API Key（v3 auth）を使用してください。長い Read Access Token には形式の注意が表示されます。
6. 追加の評価情報が必要な場合は、有効化済みの **OMDb API キー** も入力します。各公式ページから取得できます。[TMDB API 設定](https://www.themoviedb.org/settings/api) · [OMDb API キー](https://www.omdbapi.com/apikey.aspx)

## 作品を記録する

**添加观影记录**（鑑賞記録を追加）から作品を検索し、そのまま「想看」（観たい）に保存できます。「在看」（視聴中）や「已看」（鑑賞済み）も選べます。評価、日付、感想、シーズンは後から入力できます。評価を入力する場合は 1〜10 の整数、シーズンは 2 などの正の整数を使用します。

鑑賞情報の入力が終われば保存できます。ポスターはライブラリで引き続きキャッシュされ、失敗時は再試行できます。OMDb が未設定、評価が未提供、または取得に失敗した場合は追加評価が空欄になることがあります。詳細画面で IMDb と Rotten Tomatoes の評価を手動更新できます。

保存すると詳細画面が開き、鑑賞情報の編集や確認付きの削除ができます。メイン画面の検索は保存済みの作品を探すために使い、新しい作品は追加画面で検索します。

## データと現在の仕様

| 項目 | 動作 |
| --- | --- |
| 作品の識別 | メディア種別と TMDB ID で識別し、同じ作品に複数回の鑑賞履歴を保存 |
| 日付と評価 | どちらも任意。「鑑賞済み」にすると日付が空の場合のみ今日を設定し、編集画面で消去可能。評価は入力する場合のみ 1〜10 の整数 |
| 検索結果 | オンライン検索は最初のページを表示 |
| 作品情報 | 中国語を優先。中国語のあらすじが空の場合は英語を取得し、言語を表示 |
| 外部サービスの評価 | ローカルのスナップショットとして保存。OMDb の評価が取得できない場合もある |
| データベース | アプリのサンドボックス内の `Application Support/MovieJournal/MovieJournal.store` に V3 スキーマで保存 |
| ポスター | 保存済み作品は同じディレクトリ内の `Posters/` に保存。検索用サムネイルはメモリ内にキャッシュ |
| オフライン利用 | 保存済み情報とキャッシュ済みポスターの閲覧、記録の編集・削除が可能 |
| 同期とキー | データはローカルに保存し、CloudKit 同期は無効。API キーは macOS キーチェーンに保存し、iCloud キーチェーン同期は無効 |

アプリの画面は現在中国語です。ページ上部の言語リンクで README の表示言語を切り替えられます。

## ビルドとテスト

プロジェクトのルートでビルドと通常テストを実行できます。Xcode では **⌘U** を使用します。

```sh
xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' build
xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' test
```

通常テストは模擬ネットワーク応答、テスト用キー、独立した一時データベースを使用します。任意の実 TMDB API 検証は明示的に有効化する必要があり、Mac に保存された TMDB キーを読み取って API リクエストを送信します。

```sh
TEST_RUNNER_MOVIEJOURNAL_LIVE_API_TESTS=1 xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' -only-testing:MovieJournalTests/LiveAPISmokeTests test
```

実 API テストでは一時データベースを使い、検索、作品情報の取得、ポスターのキャッシュ、オフラインでの編集・削除を検証します。クリック、キーボード操作、ウィンドウを閉じる操作、オフラインでの再起動を確認する手順は開発記録に掲載しています。

## プロジェクト構成

| パス | 役割 |
| --- | --- |
| `MovieJournal/App/` | アプリのエントリーポイント |
| `MovieJournal/Models/` | バージョン付きスキーマ、作品情報、鑑賞情報の下書き、移行計画 |
| `MovieJournal/Persistence/` | ローカルコンテナ、検索、明示的な保存、重複判定、ロールバック |
| `MovieJournal/Networking/` | TMDB / OMDb リクエスト、解析、エラー処理 |
| `MovieJournal/Services/` | キーチェーン、キー検証、作品情報取得、ポスターのキャッシュと整理 |
| `MovieJournal/ViewModels/` | 追加、編集、削除、設定、ライブラリの状態管理 |
| `MovieJournal/Views/` | SwiftUI 画面と共通コンポーネント |
| `MovieJournalTests/` | Swift Testing によるテストと任意の実 API 検証 |

## 開発記録

元の README にある段階別の受け入れ確認手順、過去のテスト結果、不具合修正、署名設定、ストレージの説明を全文保存しています。過去の検証結果は、記載されたバージョンと日付に対応します。[開発記録の全文（中国語）](docs/DEVELOPMENT.zh-CN.md)

## データ提供元と謝辞

作品情報とポスターは TMDB、IMDb と Rotten Tomatoes の追加評価は OMDb から取得します。[TMDB API](https://developer.themoviedb.org/reference/intro/getting-started) · [OMDb API](https://www.omdbapi.com/)

This product uses the TMDB API but is not endorsed or certified by TMDB.
