+++
title = "dev-ai.el の Touch ID 二重認証エラーを直した話"
author = ["YAMASHITA Takao"]
date = 2026-08-15T17:01:00+09:00
lastmod = 2026-09-25T16:30:46+09:00
tags = ["Emacs", "auth-source", "touchid", "aidermacs"]
categories = ["Tech"]
draft = false
cover = ""
+++

## 症状 {#症状}

Emacs 起動直後、 `*Messages*` に以下が出力される。

```text
Decrypting /Users/ac1965/.authinfo.gpg...done
```

一見すると成功しているように見えるが、その直後にエラーが出る。ログを見る限り
`dev-ai` 側の認証処理そのものは通っており、原因はどうやら別の depth-10/20 系
フックにありそうだ、というところから調査を始めた。


## 根本原因は2つ重なっていた {#根本原因は2つ重なっていた}


### 1. DEPTH 修正だけでは不十分だった {#1-dot-depth-修正だけでは不十分だった}

以前の修正で `leaf` の DEPTH 10 を直し、フックの実行順序自体は正しくなって
いた。しかし問題の本質はそこではなく、「Emacs 起動のたびに無条件で認証処理を
走らせる」という設計そのものにあった。

{{< details "以前の修正: add-hook の DEPTH を明示した話" >}}
Emacs 27 以降、`add-hook` は第3引数に DEPTH を取れる。値が小さいほど先に
実行され、省略時は 0 扱いになる。同じ 0 のフック同士は登録順（＝require や
leaf の展開順）に依存してしまうため、依存関係のあるフックを安全に順序付け
るには DEPTH を明示するのが定石。

```emacs-lisp
;; 修正前: DEPTH 未指定 (どちらも暗黙の 0)
;;   → 実行順序が leaf の展開順に依存し、環境変数を参照する側が
;;      先に呼ばれてしまうことがあった
(add-hook 'after-init-hook #'my/env-setup)
(add-hook 'after-init-hook #'dev-ai--setup-api-key)

;; 修正後: DEPTH を明示し、依存元 (env-setup) を確実に先に実行する
(add-hook 'after-init-hook #'my/env-setup -10)          ; 先に実行
(add-hook 'after-init-hook #'dev-ai--setup-api-key 10)  ; 後に実行
```

これで `dev-ai--setup-api-key` が `my/env-setup` より後に走ることは保証
されたが、後述の通り「起動のたびに毎回認証処理そのものが走る」という設計
上の問題は解消されておらず、Touch ID 二重要求バグの根本原因は別にあった。
{{< /details >}}


### 2. auth-source-backends はキャッシュを持たない {#2-dot-auth-source-backends-はキャッシュを持たない}

`(auth-source-backends)` は呼び出すたびに `~/.authinfo.gpg` を再パース、
つまり GPG での再復号を行う。ここが今回の本丸だった。

旧実装の `dev-ai--setup-api-key` は、

-   openrouter.ai
-   api.openai.com

に対して `auth-source-search` を個別に2回呼んでいた。結果として Emacs 起動
直後に Touch ID の生体認証が短時間に2回連続で要求され、2回目が

```text
No secret key
```

で失敗していた。原因は LAContext が極端に短い間隔で連続評価できないという
macOS 側の制約で、実装のロジックエラーというより「認証コストの見積もりが
甘かった」ことに起因する。


## 修正内容 {#修正内容}


### Before: 個別に2回検索していた旧実装 {#before-個別に2回検索していた旧実装}

```emacs-lisp
(defun dev-ai--setup-api-key ()
  "Configure API keys for dev-ai on every startup."
  (let ((openrouter-key
         (auth-source-pick-first-password :host "openrouter.ai"))
        (openai-key
         (auth-source-pick-first-password :host "api.openai.com")))
    (when openrouter-key
      (setenv "OPENROUTER_API_KEY" openrouter-key))
    (when openai-key
      (setenv "OPENAI_API_KEY" openai-key))))

(add-hook 'after-init-hook #'dev-ai--setup-api-key)
```

`auth-source-pick-first-password` は内部で `auth-source-search` →
`auth-source-backends` を呼ぶため、host ごとに呼べば呼ぶほど
`~/.authinfo.gpg` の再復号 = Touch ID 要求が発生する。ここでは2回。しかも
`after-init-hook` に載せているため、aidermacs を一度も使わない起動でも
無条件に発火していた。


### After: 検索を1回にまとめ、遅延実行に変更 {#after-検索を1回にまとめ-遅延実行に変更}

```emacs-lisp
(defvar dev-ai--api-key-configured nil
  "Non-nil once API keys have been configured for this session.")

(defun dev-ai--setup-api-key ()
  "Configure API keys for dev-ai, once per session, on demand."
  (unless dev-ai--api-key-configured
    (let* ((hosts '("openrouter.ai" "api.openai.com"))
           (entries (auth-source-search :host hosts :max 2))
           (openrouter (seq-find
                        (lambda (e) (equal (plist-get e :host) "openrouter.ai"))
                        entries))
           (openai (seq-find
                    (lambda (e) (equal (plist-get e :host) "api.openai.com"))
                    entries)))
      (when openrouter
        (setenv "OPENROUTER_API_KEY"
                (funcall (plist-get openrouter :secret))))
      (when openai
        (setenv "OPENAI_API_KEY"
                (funcall (plist-get openai :secret))))
      (setq dev-ai--api-key-configured t))))

(advice-add 'aidermacs-run :before #'dev-ai--setup-api-key)
```

ポイントは3つ。

1.  `:host` にリストを渡して `auth-source-search` を1回だけ呼ぶ。これで
    `~/.authinfo.gpg` の復号 = Touch ID 要求も1回に減る。
2.  結果の `entries` を `seq-find` で host ごとに振り分ける。
    `auth-source-search` が返す各エントリの `:secret` は関数なので、値を
    取り出すには `funcall` が要る点に注意。
3.  `after-init-hook` を削除し、 `aidermacs-run` への `:before` advice に
    置き換える。これで認証コストは「実際に aidermacs を呼んだ最初の1回」
    にのみ発生する。 `dev-ai--api-key-configured` フラグでその1回に固定して
    いるので、2度目以降の `aidermacs-run` では認証処理自体スキップされる。


## 検証 {#検証}

`README.org` を編集し `make tangle` で再生成。以下のチェックはすべて通過。

-   check-cookies
-   check-tangle
-   check-emphasis
-   check-fboundp-guards
-   leaf マクロ展開テスト

残るのは修正前から既知の3件のみで、今回のリグレッションはなし。


## 確認方法 {#確認方法}

1.  Emacs を再起動する
2.  `*Messages*` に `Decrypting /Users/ac1965/.authinfo.gpg...` が _出ない_
    ことを確認する
3.  `M-x aidermacs-run` を実行したときだけ Touch ID が1回聞かれることを確認
    する


## 残課題 {#残課題}

`my/auth-gpg-verify` は Anthropic / OpenRouter / OpenAI の3エントリを個別に
ループで検索する実装のままなので、実行すると同じ理由で Touch ID が3回連続
要求される可能性がある。これは手動診断用のコマンドであり日常のワークフロー
には乗らないため今回は据え置いたが、気になるようであれば同じ要領でまとめて
直せる。


## その後の対応 {#その後の対応}

上記の残課題についても、同じパターンで修正した。

```emacs-lisp
;; Before: host ごとに個別ループで検索 → Touch ID が3回連続要求される
(defun my/auth-gpg-verify ()
  "Manually verify GPG-backed auth-source entries."
  (interactive)
  (dolist (host '("api.anthropic.com" "openrouter.ai" "api.openai.com"))
    (let ((secret (auth-source-pick-first-password :host host)))
      (message "%s: %s" host (if secret "OK" "NG")))))
```

```emacs-lisp
;; After: :host にリストを渡して1回の auth-source-search にまとめる
(defun my/auth-gpg-verify ()
  "Manually verify GPG-backed auth-source entries."
  (interactive)
  (let* ((hosts '("api.anthropic.com" "openrouter.ai" "api.openai.com"))
         (entries (auth-source-search :host hosts :max (length hosts))))
    (dolist (host hosts)
      (let* ((entry (seq-find
                      (lambda (e) (equal (plist-get e :host) host))
                      entries))
             (secret (and entry (funcall (plist-get entry :secret)))))
        (message "%s: %s" host (if secret "OK" "NG"))))))
```

`dev-ai--setup-api-key` のときと同じく、=:host= にリストを渡して検索を
1回にまとめただけで、GPG の復号 = Touch ID 要求も1回に減った。診断コマンド
自体の役割は変えていないので、動作確認は `M-x my/auth-gpg-verify` を実行
し、Touch ID が1回しか要求されないこと、かつ3ホスト分の結果が `*Messages*`
に出力されることの2点を見るだけでよい。

これで dev-ai 周りの GPG/Touch ID 関連の重複認証は、通常起動時・aidermacs
使用時・手動診断時のいずれの経路でも解消したことになる。


## まとめ {#まとめ}

「起動時に毎回認証する」設計と「auth-source-backends が無キャッシュである」
という2つの事実が重なって初めて表面化するタイプのバグだった。DEPTH の修正
のように実行順序だけを直しても再現し続けたのはこのためで、認証処理そのもの
を「必要になるまで呼ばない」設計に変えたことで解消した。GPG 経由の秘密情報
アクセスを Emacs Lisp から扱う際は、呼び出し回数そのものがコスト（かつ
macOS 側の制約でエラー要因）になり得る、という点は覚えておきたい。
