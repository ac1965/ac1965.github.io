+++
title = "通常起動の Emacs だけ dark テーマの背景が崩れた話"
author = ["YAMASHITA Takao"]
date = 2026-10-12T07:48:00+09:00
lastmod = 2026-10-17T20:50:04+09:00
tags = ["Emacs", "Nano-Theme", "Debug"]
categories = ["Tech"]
draft = false
cover = ""
+++

自分の Emacs 設定では、テーマに nano を使っている。少し変更した後の確認で、気がついた。

daemon 経由の `emacsclient` で起動すると期待どおりの dark になるのに、daemon なしの通常起動だけ背景が崩れる。
背景は明るいまま、文字色だけが dark 用の明るい色になっていて、判読しにくい状態だった。
Eydaemon 経由の `emacsclient` で起動した場合は、期待どおりの dark になる。

{{< figure src="nano-dark-expected.webp" caption="<span class=\"figure-number\">Figure 1: </span>emacsclient（daemon）で起動した場合。期待どおりの dark" >}}

一方、通常起動では、背景が明るいまま文字だけが dark 用の色になり、崩れる。

{{< figure src="nano-dark-broken.webp" caption="<span class=\"figure-number\">Figure 2: </span>通常起動（daemon なし）で崩れた状態" >}}


## 最初の仮説と、足りなかった修正 {#最初の仮説と-足りなかった修正}

最初に疑ったのは、フレームの色パラメータだ。nano-theme の `nano-dark` は `default-frame-alist` を書き換えるだけで、すでに存在するフレームの `background-color` / `foreground-color` には触れない。daemon ならテーマ適用後にフレームが作られるので問題にならないが、通常起動では起動時に作られた初期フレームが light のまま残る。そう考えて、既存フレームへ色を反映する関数を足した。

```emacs-lisp
(defun ui-theme--sync-frame-colors ()
  "`default-frame-alist' の背景・前景色を既存の全グラフィカルフレームへ反映する。"
  (dolist (frame (frame-list))
    (when (display-graphic-p frame)
      (dolist (key '(background-mode background-color foreground-color))
        (let ((entry (assq key default-frame-alist)))
          (when entry
            (set-frame-parameter frame key (cdr entry))))))))
```

再起動しても、崩れは直らなかった。

{{< figure src="nano-dark-still-broken.webp" caption="<span class=\"figure-number\">Figure 3: </span>最初の修正後も、通常起動では背景が light のまま" >}}


## 推測をやめて、実機の値を取る {#推測をやめて-実機の値を取る}

そこで、通常起動の Emacs を実際に立ち上げ、起動 6 秒後にフレームとフェイスの色をファイルへ書き出して終了する調査用スクリプトを使った。

```emacs-lisp
(run-with-timer 6 nil
 (lambda ()
  (with-temp-file (expand-file-name "dump.txt" (file-name-directory (or load-file-name "/path/to/scratchpad/x")))
   (dolist (f (frame-list))
    (insert (format "frame %S gfx=%S bgmode-param=%S bg=%S fg=%S\n" f (display-graphic-p f) (frame-parameter f 'background-mode) (frame-parameter f 'background-color) (frame-parameter f 'foreground-color))))
   (insert (format "fbm=%S default bg=%S fg=%S enabled=%S\n alist=%S\n nano-dark-bg=%S\n" frame-background-mode (face-background 'default nil) (face-foreground 'default nil) custom-enabled-themes default-frame-alist (and (boundp 'nano-dark-background) nano-dark-background)))
   (insert (format "highlight=%S hl-line=%S\n" (face-background 'highlight nil) (face-background 'hl-line nil))))
  (kill-emacs)))
```

起動は次のようにした。

```bash
emacs --init-directory ~/.emacs.d-stable -l dump.el
```

出力のうち、肝心な部分は次のとおり。

```text
frame #<frame  0x7682641b88> gfx=t bgmode-param=dark bg="#fafafa" fg="#ECEFF4"
fbm=dark default bg="#fafafa" fg="#ECEFF4" enabled=(nano)
 alist=((foreground-color . "#ECEFF4") (background-color . "#2E3440") (background-mode . dark) ...)
 nano-dark-bg="#2E3440"
```

`background-mode` は dark で、 `default-frame-alist` の背景も dark の `#2E3440` だった。それなのに、 `default` フェイスの背景とフレームの背景色だけが light の `#fafafa` になっていた。設定上は dark なのに、実際の背景だけが light という食い違いである。


## 原因 {#原因}

通常起動では、起動時にまず light パレットが `default` フェイスの背景へ `#fafafa` を `set-face-attribute` で直接書き込む。その後に保存済みの dark を復元するのだが、dark 側の処理は `default` だけを復元対象から外していた。このため背景だけが light のまま残り、前景は dark 用の明るい色になって、画面の崩れになった。daemon では、この順序にならないので起きない。


## 修正 {#修正}

dark の分岐で、 `default` の背景・前景を dark の色へ明示的に戻すようにした。

```emacs-lisp
;; light パレットが `set-face-attribute' で default に焼き込んだ背景色は
;; face-spec-recalc では消えない。通常起動では light の適用後に dark へ
;; 切り替わるため、dark の色を明示して上書きする。
(let ((bg (ui-nano--dark-color 'nano-dark-background))
      (fg (ui-nano--dark-color 'nano-dark-foreground)))
  (when (and bg fg)
    (ui-nano--safe-face 'default :background bg :foreground fg)))
```

同じスクリプトで再確認すると、 `default` の背景もフレームの背景も `#2E3440` になっていた。

```text
frame #<frame  0x7c80658b88> gfx=t bgmode-param=dark bg="#2E3440" fg="#ECEFF4"
fbm=dark default bg="#2E3440" fg="#ECEFF4" enabled=(nano)
```


## まとめ {#まとめ}

-   最初の仮説(フレームの色パラメータ)は、原因の一部しか押さえていなかった。
-   起動順序によって結果が変わる問題は、実際に起動して値を取ると、どの値が食い違っているかが一目で分かる。
-   今回の食い違いは、フレームの色ではなく `default` フェイスにあった。
