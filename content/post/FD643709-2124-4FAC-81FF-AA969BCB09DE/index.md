+++
title = "org-capture 中に ox-hugo の記事をブラウザでプレビューできるようにした"
author = ["YAMASHITA Takao"]
date = 2026-08-11T09:55:00+09:00
lastmod = 2026-09-25T19:59:32+09:00
tags = ["Emacs", "Ox-Hugo", "Org-Capture", "Markdown-Preview-Mode"]
categories = ["Tech"]
draft = false
cover = ""
+++

ox-hugo で all-posts.org からブログを書いているのだが、キャプチャ中に記事の見た目を確認する手段がなかった。 `C-c C-c` で確定してエクスポートするまで、Markdown に変換された状態を見られない。これを直したくて、キャプチャ中に 1 キーでブラウザプレビューできる機能を `orgx-auto-hugo.el` に足した。

割り当てたキーは `org-capture-mode-map` の `C-c C-p` 。押すたびに、その時点のエントリを `markdown-preview-mode` でブラウザに表示する。確定でも中断でもない、独立した下書き確認用のコマンドという位置づけにした。

**実装で一番悩んだところ**

素直に考えると `org-hugo-export-wim-to-md` を一時ディレクトリ向けに呼べばよさそうに思えるが、これは避けた。理由は、キャプチャ対象ファイル（ `my:f:capture-blog-file` ）自体に `#+HUGO_BASE_DIR` が設定されている可能性が高く、それがあると動的束縛で `org-hugo-base-dir` を一時ディレクトリに上書きしても、キーワード側が優先されてしまうから。うっかりすると、プレビューのつもりが実際の content ディレクトリに書き込んでしまう。

そこで代わりに `org-export-as` を `SUBTREEP` 付きで直接呼び、今のエントリをメモリ上の文字列としてだけレンダリングするようにした。ディスクにはまったく触れないので、 `org-hugo-base-dir` の解決経路そのものが関係なくなる。

セッション中に使う一時ファイルの場所は、バッファローカル変数ではなく `org-capture-put` / `org-capture-get` で持たせている。キャプチャバッファは確定・中断のどちらでも `org-capture-after-finalize-hook` の前後で kill される可能性があり、バッファローカル変数だと後始末のタイミングで参照できなくなることがあるからだ。実際、後始末（一時ディレクトリの削除）は `org-capture-after-finalize-hook` に登録した別関数で、確定・中断の両方で走るようにしてある。

`ox-hugo` と `markdown-preview-mode` はどちらもプレビュー実行時にだけ `require` している。これは既存の `orgx-auto-hugo.el` が確定時のエクスポートで踏襲していたのと同じ方針で、トップレベルで `require` すると Org の遅延ロードが崩れてしまうためだ。

**エラーと直し方**

実際に `C-c C-p` を使ってみたら、こういうエラーが出た:

```text
org-babel-exp process emacs-lisp at position 265000...
Saving file /var/folders/0v/0kv2fkk10hgctjjqnyxgg4r00000gn/T/orgx-hugo-preview-KghsSQ/preview.md...
Wrote /var/folders/0v/0kv2fkk10hgctjjqnyxgg4r00000gn/T/orgx-hugo-preview-KghsSQ/preview.md
markdown-preview--send-preview-to: Wrong type argument: number-or-marker-p, nil
```

ログを見ると、 `preview.md` の保存自体（ `Saving file...` / `Wrote ...` ）は普通に成功している。エラーになっているのは `markdown-preview-mode` がブラウザへ現在の表示位置を送る内部処理（ `markdown-preview--send-preview-to` ）の方で、これはプレビューバッファの window の状態を見に行く。ところが `find-file-noselect` で開いただけのバッファは、そもそもどの window にも表示していない。それで nil が渡っていた。

直し方は、 `erase-buffer` / `insert` / `save-buffer` / モード有効化の一連の処理を、 `pop-to-buffer` で実際に window に表示した状態でやるようにしたこと。処理が終わったら、元のキャプチャバッファへフォーカスを戻す。モードの有効化自体は `ignore-errors` で包んでおいた。送信に失敗する時点で、サーバの起動もモードの有効化も既に済んでいるので、そこだけ落ちても後続を止めない。

```emacs-lisp
(defun orgx-auto-hugo-preview-capture ()
  "Render the entry currently being captured through ox-hugo and show it in
`markdown-preview-mode' as a one-shot browser preview. Does not finalize or
abort the capture, and never writes into the real Hugo content tree."
  (interactive)
  (unless (bound-and-true-p org-capture-mode)
    (user-error "orgx-auto-hugo-preview-capture: not in an org-capture buffer"))
  (require 'ox-hugo)
  (require 'markdown-preview-mode)
  (let ((md-string
         (condition-case err
             (org-export-as 'hugo t nil nil nil)
           (error
            (message "[orgx-auto-hugo] preview export failed: %s"
                     (error-message-string err))
            nil))))
    (when md-string
      (let* ((capture-buf (current-buffer))
             (file (orgx-auto-hugo-preview--scratch-file))
             (buf (find-file-noselect file)))
        (save-selected-window
          (pop-to-buffer buf)
          (erase-buffer)
          (insert md-string)
          (save-buffer)
          (ignore-errors
            (unless (bound-and-true-p markdown-preview-mode)
              (markdown-preview-mode 1))))
        (when (buffer-live-p capture-buf)
          (pop-to-buffer capture-buf))
        (message "[orgx-auto-hugo] preview updated.")))))

(with-eval-after-load 'org-capture
  (keymap-set org-capture-mode-map "C-c C-p" #'orgx-auto-hugo-preview-capture))
```
