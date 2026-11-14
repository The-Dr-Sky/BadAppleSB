# BadAppleSB

iOS / iPadOSのホーム画面にあるアプリアイコンをドットに見立てて、影絵動画と音声を再生するSpringBoard向けrootless Tweakです。ホーム画面の余白を10秒間長押しすると、端末にインストールされているアプリアイコンが画面全体へ並び、映像と同期して音声が流れます。

## 動作仕様

発動操作はホーム画面上の余白に対する10秒間の長押しです。アプリアイコン、ウィジェット、Dock、下部の検索ボタン、ステータスバー領域への操作や、フォルダを開いている状態などでは反応しません。長押しの途中でホーム画面がアイコン編集モードに入った場合は、再生開始と同時に編集モードを解除します。

描画時は`SBHIconManager`からアプリアイコン画像を収集（キャッシュAPIはOSごとの差異を吸収するフォールバック付き）し、隣り合うセル同士で同じアイコンが並ばないようにランダム配置します。縦向き固定のホーム画面上でも描画ステージを時計回りに90度回転して配置するため、画面上辺（ノッチ側）が左になる横向きでの表示です。4:3の比率を保ったまま画面全体へAspect Fillで敷き詰めるので、映像の上下端は画面外へ見切れます。画面外のセルは描画対象から外し、毎フレーム値が変化したセルだけ透明度を更新します。また、iPadOSなどDockが別ウィンドウ（`SBFloatingDockWindow`）に分かれている環境では、再生中にDockウィンドウも合わせてフェードアウトし、終了時に元の状態へ戻します。

音声は`AVAudioSessionCategoryPlayback`と`AVAudioPlayer`を使って端末の音量設定に応じた音量で再生し、再生時刻に合わせて`CADisplayLink`でフレームを進めます。開始時に画面へ「ダブルタップで終了」の案内を2.5秒間表示し、ダブルタップ、画面ロック、カバーシート表示、ホーム画面からの遷移、音声再生の終了のいずれかで元のホーム画面へ戻ります。

## 動作確認済みの環境と前提

このTweakは非公開APIの`SpringBoard`と`SpringBoardHome`をフックします。以下のrootless環境で動作確認済みです（パッケージの依存条件は`mobilesubstrate (>= 0.9.5000)`と`firmware (>= 17.0)`です）。

- **iPhone 12 mini**（`iPhone13,1` / iOS 17.0 ビルド`21A329` / Dopamine 3.0.13 rootless）
- **vphone仮想環境**（`iPad17,3` / iOS 27.0.1 ビルド`24A446` / ElleKit rootless、ポートレート画面で確認）

従来の`SBIconController`ベースの構成に加え、27.0.1のように`SBHomeScreenController`へ移行した構成や、`SBHIconImageCache`のアイコン取得API変更・別ウィンドウの`SBFloatingDockWindow`構成にも対応しています。

ソースとなる動画ファイルと、変換後のバイナリおよび音声ファイルはリポジトリに含めていません。ビルドする前に、利用者側で用意した動画ファイルからアセットを生成してください。

## ビルドとインストール

ビルドにはTheos環境、Python 3、`ffmpeg`が必要です。環境変数`THEOS`が未設定のときは`Makefile`の設定により`~/theos`を参照します。

最初にリポジトリ直下へ動画ファイル（`.webm`、`.mp4`、`.mkv`、`.mov`）を置くか、パスを指定して変換スクリプトを実行してください。実行すると、`layout/Library/Application Support/BadAppleSB/`配下へ`72x54`グリッド・`30fps`のフレームデータ`badapple.bin`とAAC音声ファイル`badapple.m4a`が生成されます。

```bash
python3 scripts/generate_assets.py --input /path/to/video.webm
```

続いて、rootless向けの`.deb`パッケージ（`arm64` / `arm64e`）をビルドしてください。

```bash
make clean package FINALPACKAGE=1
```

ビルドが終わったら、`packages/`に出力された`com.yyyywaiwai.badapplesb_0.1.0_iphoneos-arm64.deb`を端末へ転送してインストールし、SpringBoardを再読み込みしてください。

```bash
dpkg -i com.yyyywaiwai.badapplesb_0.1.0_iphoneos-arm64.deb
sbreload
```

## 使い方

1. ホーム画面のアイコンや検索ボタンがない余白を10秒間長押ししてください。
2. 触覚フィードバックとともに画面が暗転し、画面上辺（ノッチ側）を左にした横向きで再生が始まります。
3. 途中で止めたいときは画面をダブルタップするか、電源ボタンで画面をロックしてください。

## ファイル構成

| パス | 役割 |
|---|---|
| `.gitignore` | ビルド成果物・動画ファイル・生成アセットの除外設定 |
| `Makefile` | Theosビルド設定（rootless・`arm64` / `arm64e`・iOS 17.0ターゲット） |
| `control` | Debianパッケージのメタデータ定義 |
| `BadAppleSB.plist` | フック対象（`com.apple.springboard`）のフィルタ定義 |
| `scripts/generate_assets.py` | 動画から`badapple.bin`と`badapple.m4a`を生成するスクリプト |
| `src/Tweak.x` | `SBHomeScreenViewController`、`SBIconController`（iOS 17系）、`SBHomeScreenController`（新世代Home画面）へのLogosフック |
| `src/BadApplePrivate.h` | 使用するSpringBoard内部クラスのヘッダ宣言 |
| `src/BadAppleController.h` / `.m` | 長押し判定、アセット読込、アイコン・Dock表示制御、音声再生とフレーム同期の制御 |
| `src/BadAppleCanvasView.h` / `.m` | 90度回転、Aspect Fillレイアウト、`CALayer`によるドット描画 |

## 注意事項

iOS 17.0および27.0.1環境で動作を確認していますが、未確認のOSバージョンや脱獄環境ではSpringBoard内部のクラス構造やメソッド名の違いにより動作しない場合があります。また、iPadOSなどでアイコンやDockを長押ししてコンテキストメニューを開いた直後（閉鎖アニメーション中）は、タッチがホーム画面へ届かず長押し判定が開始されないことがあります。音声再生時は端末の音量設定に従って音が出るため、再生前に音量を確認してください。
