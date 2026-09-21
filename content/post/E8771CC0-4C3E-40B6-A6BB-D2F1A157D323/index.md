+++
title = "Claude on Safari"
author = ["YAMASHITA Takao"]
date = 2026-07-05T16:38:00+09:00
lastmod = 2026-09-21T15:24:00+09:00
tags = ["Safari", "Claude"]
categories = ["Tech"]
draft = false
+++

macOS デスクトップアプリ版の Claude で、たまにチャット入力欄がフリーズすることがある。特にシークレットチャットで固まると、履歴が残らないぶん地味に悲しい。

ブラウザ版ならリロードすれば復帰できるので助かるのだが、今度は Safari 特有の別の問題にぶつかった。日本語入力で変換を確定するために押した Enter キーが、そのままメッセージ送信として扱われてしまうのだ。これはこれでストレスが溜まる。


## 原因：ブラウザは「確定のEnter」と「送信のEnter」を区別できない {#原因-ブラウザは-確定のenter-と-送信のenter-を区別できない}

調べてみると、原因はブラウザの仕組みにあるらしい。

日本語IMEを使っているとき、変換候補を確定するための「確定Enter」と、メッセージを送るための「送信Enter」は、ブラウザ側からはどちらも単なる `event.key === 'Enter'` にしか見えない。本来なら `compositionstart` / `compositionend` イベントを使って「いま入力中かどうか」を判定すべきところだが、Safari はこのイベントの取りこぼしが Chrome より目立つらしく、確定した直後の Enter がそのまま送信として伝わってしまう。


## 対策：Userscripts でこのサイトだけピンポイントに直す {#対策-userscripts-でこのサイトだけピンポイントに直す}

対処法をいくつか検討したが、直したいのは claude.ai だけなので、Safari 拡張機能の Userscripts（開発者：Justin Wasack）でピンポイントに対応することにした。Mac App Store から無料でインストールできるのも決め手のひとつ。

手順は次のとおり。Userscripts をインストールしたら Safari の拡張機能から有効化し、ツールバーのアイコンをクリックして出てくる画面から進める。

{{<details "手順">}}
1. ポップアップ下部の「Open Extension Page」をクリック
2. 新しいSafariタブで拡張機能の管理ページ（フル画面のエディタ画面）が開く
3. 画面内の「+」ボタンまたは「New Script」的なボタンをクリックして、新規JavaScriptファイルを作成
   エディタが開いたら、テンプレートコードを全て削除し、以下のJavaScriptコードを貼り付ける
{{</details>}}

貼り付けるコードはこちら。

```javascript
// ==UserScript==
// @name         Claude.ai IME Enter Fix (Safari)
// @namespace    local
// @version      1.0
// @match        https://claude.ai/*
// @run-at       document-start
// @grant        none
// ==/UserScript==
(function () {
  'use strict';
  let isComposing = false;
  let lastCompositionEndTime = 0;
  const THRESHOLD_MS = 300;

  document.addEventListener('compositionstart', () => {
    isComposing = true;
  }, true);

  document.addEventListener('compositionend', () => {
    isComposing = false;
    lastCompositionEndTime = Date.now();
  }, true);

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      const withinGuard = isComposing ||
        (Date.now() - lastCompositionEndTime < THRESHOLD_MS);
      if (withinGuard) {
        event.stopImmediatePropagation();
        event.preventDefault();
      }
    }
  }, true);
})();
```

保存できたら、実際にちゃんと動くか試してみよう。

{{<details "動作検証">}}
  1. claude.aiのチャット入力欄をクリック
  2. 日本語入力モードで「かんじへんかん」と入力
  3. スペースキーで変換候補を「漢字変換」に確定
  4. Enterキーを押す
     → メッセージが送信されず、変換だけが確定されればOK
  5. 送信したい時は改めてEnterキー（変換確定から300ms経過後）を押す、または通常の送信ボタンをクリック
{{</details>}}

これで問題なければ、日本語入力中の誤送信フラストレーションからは解放されるはず :-)


## おまけ：なぜこれで直るのか {#おまけ-なぜこれで直るのか}

気になる人向けに、仕組みをもう少し詳しく書いておく。

{{<details "仕組みの詳細">}}
このスクリプトは、Safari版claude.aiのDOMにJavaScriptを注入して、ブラウザ標準のEnterキー処理を「横取り」する方式。claude.ai本体のページ実装は一切いじらず、ブラウザ拡張機能側でイベントを先に受け取ってキャンセルしているだけだ。

1. IME状態の追跡
   compositionstart（変換開始）とcompositionend（変換終了＝確定）を監視して、「今まさに日本語入力中かどうか」をフラグで持っておく。
2. 確定直後の猶予期間
   compositionendが発火してから実際にEnterのkeydownイベントが届くまで、数十ms〜200ms程度のラグが出ることがある（特にSafariで顕著）。「入力中フラグ」だけだと確定直後のEnterを取りこぼしてしまうので、compositionendが起きた時刻を記録しておき、そこから一定時間（300ms程度）以内のEnterも「変換確定由来」とみなしてブロックする。
3. キャプチャフェーズでの割り込み
   addEventListener('keydown', fn, true)の第3引数trueでキャプチャフェーズに登録する。これでclaude.ai本体のイベントリスナー（バブリングフェーズで動作）より先にこのスクリプトが実行され、event.stopImmediatePropagation()とevent.preventDefault()で送信処理そのものへの到達をブロックできる、という仕組み。
{{</details>}}
