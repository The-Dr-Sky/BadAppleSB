# BadAppleSB

iOSのホーム画面にあるアプリアイコンをドットに見立てて、影絵動画と音声を再生するSpringBoard向けrootless Tweakです。ホーム画面の余白を10秒間長押しすると、端末にインストールされているアプリアイコンが画面全体へ並び、映像と同期して音声が流れます。

## 動作仕様

発動操作はホーム画面上の余白に対する10秒間の長押しです。アプリアイコンや下部の検索ボタン、ステータスバー領域への操作、フォルダを開いている状態などでは反応しません。長押しの途中でホーム画面がアイコン編集モードに入った場合は、再生開始と同時に編集モードを解除します。

描画時は`SBHIconManager`から表示中のアプリアイコン画像を収集し、隣り合うセル同士で同じアイコンが並ばないようにランダム配置します。縦向き固定のホーム画面上でも描画ステージを時計回りに90度回転して配置するため、ノッチ側が左になる横向きでの表示です。4:3の比率を保ったまま横画面全体へAspect Fillで敷き詰めるので、映像の上下端は画面外へ見切れます。画面外のセルは描画対象から外し、毎フレーム値が変化したセルだけ透明度を更新します。

音声は`AVAudioSessionCategoryPlayback`と`AVAudioPlayer`を使って端末の音量設定に応じた音量で再生し、再生時刻に合わせて`CADisplayLink`でフレームを進めます。開始時に画面へ「ダブルタップで終了」の案内を2.5秒間表示し、ダブルタップ、画面ロック、カバーシート表示、ホーム画面からの遷移、音声再生の終了のいずれかで元のホーム画面へ戻ります。

## 動作確認済みの環境と前提

このTweakは非公開APIの`SpringBoard`と`SpringBoardHome`をフックします。実機確認はiOS 17.0（ビルド`21A329`）とDopamine 3.0.13（rootless）を導入したiPhone 12 mini（`iPhone13,1`）で行いました。パッケージの依存条件は`mobilesubstrate (>= 0.9.5000)`と`firmware (>= 17.0)`です。

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
2. 触覚フィードバックとともに画面が暗転し、ノッチ側を左にした横向きで再生が始まります。
3. 途中で止めたいときは画面をダブルタップするか、電源ボタンで画面をロックしてください。

## ファイル構成

| パス | 役割 |
|---|---|
| `.gitignore` | ビルド成果物・動画ファイル・生成アセットの除外設定 |
| `Makefile` | Theosビルド設定（rootless・`arm64` / `arm64e`・iOS 17.0ターゲット） |
| `control` | Debianパッケージのメタデータ定義 |
| `BadAppleSB.plist` | フック対象（`com.apple.springboard`）のフィルタ定義 |
| `scripts/generate_assets.py` | 動画から`badapple.bin`と`badapple.m4a`を生成するスクリプト |
| `src/Tweak.x` | `SBIconController`と`SBHomeScreenViewController`へのLogosフック |
| `src/BadApplePrivate.h` | 使用するSpringBoard内部クラスのヘッダ宣言 |
| `src/BadAppleController.h` / `.m` | 長押し判定、アセット読込、音声再生とフレーム同期の制御 |
| `src/BadAppleCanvasView.h` / `.m` | 90度回転、Aspect Fillレイアウト、`CALayer`によるドット描画 |

## 注意事項

iOS 17.0以外のバージョンでは、SpringBoard内部のクラス構造やメソッド名の違いにより動作しない場合があります。また、音声再生時は端末の音量設定に従って音が出るため、再生前に音量を確認してください。
