+++
title = "condition-case と catch はバイトコードでどう動くのか"
author = ["YAMASHITA Takao"]
date = 2026-10-11T17:16:00+09:00
lastmod = 2026-10-11T18:24:16+09:00
tags = ["Emacs", "Elisp", "C"]
categories = ["Tech"]
draft = false
cover = ""
+++

「 `condition-case` と `catch` は、バイトコードエンジンの中でどう実装されているのか」を読んでみた。

読んだのは `emacs-mirror/emacs` の 2026-10-10 時点（ `2743882114c` ）である。

ソースを読んだだけでは心もとないので、手元の Emacs 32.0.50 で小さな関数を自分で書き、逆アセンブルして実行し、読んだ内容と突き合わせた。確かめたのは、その自作関数の実行結果までである。

結論から言うと、 `condition-case` も `catch` も C の `setjmp` / `longjmp` で実装されていた。 `throw` も `signal` も、最後は `unwind_to_catch` で `longjmp` して戻る。

読み進める中で、最初の推測を 1 つ訂正することになった。さらに、 `handler-bind` で再現できた不具合候補も 1 件見つけた。


## 全体像 {#全体像}

まず、1 回の実行で通る制御の流れを図にしてみた。静的な呼び出し関係ではない。

{{< mermaid >}}
flowchart TD
    A["Bpushcatch / Bpushconditioncase<br/>bytecode.c:967-1007"] -->|"push_handler で handlerlist に積む<br/>sys_setjmp で復帰点を保存"| H[("handlerlist<br/>(struct handler の連結リスト)")]
    T["Fthrow<br/>eval.c:1464"] -->|"tag が EQ の CATCHER を探索"| U
    S["signal_or_quit<br/>eval.c:1943"] -->|"conditions が合う<br/>CONDITION_CASE を探索"| U
    H --> T
    H --> S
    U["unwind_to_catch<br/>eval.c:1422"] -->|"specpdl を unbind し<br/>handlerlist を巻き戻す"| L["sys_longjmp(catch->jmp, 1)"]
    L --> R["bytecode.c:978 の if 内に復帰<br/>top / pc を handler から復元<br/>値を PUSH して op_branch へ"]
{{< /mermaid >}}

要は、ハンドラを積んでおいて、 `throw` や `signal` のときに探して、見つかったら `longjmp` で戻る、という話である。


## ハンドラ構造体 {#ハンドラ構造体}

`struct handler` は `lisp.h:3840` にある。

種類（ `handlertype` ）は `CATCHER` 、 `CONDITION_CASE` 、 `CATCHER_ALL` 、 `CATCHER_ALL_DEBUGGABLE` 、 `HANDLER_BIND` 、 `SKIP_CONDITIONS` の 6 つ（ `lisp.h:3804` ）。

バイトコード用に `bytecode_top` と `bytecode_dest` というフィールドがある（ `lisp.h:3857-3858` ）。バイトコードは同時に複数のハンドラを持てるので、復帰時にスタックの高さと飛び先を知る必要がある。だからハンドラ自身にその情報を持たせているわけだ。

あとは、 `setjmp` で戻る側が復元できるように、次の状態を保存している。

-   `jmp`
-   `pdlcount` （specpdl の深さ）
-   `f_lisp_eval_depth`
-   `act_rec` （バイトコードのフレーム）
-   `poll_suppress_count`
-   `interrupt_input_blocked`

積むのは `push_handler_nosignal` で、空きのある `nextfree` を再利用し、無ければ `malloc` する（ `eval.c:1839-1866` ）。


## バイトコード側 {#バイトコード側}

`bytecode.c:967-1011` が該当する。

`Bpushcatch` と `Bpushconditioncase` は `type` だけが違って、 `pushhandler:` のラベルを共有している。

登録はこうなる。タグ（または条件リスト）をスタックから `POP` して `push_handler` に渡す。続けて `bytecode_dest = FETCH2` （ハンドラ本体の飛び先）と `bytecode_top = top` （登録時のスタック位置）を保存して、 `sys_setjmp` を呼ぶ。

`sys_setjmp` が非 0 で戻ってきたとき（ `bytecode.c:978-1004` ）は、次の順に処理する。

1.  `quitcounter` を `-1` にする。次の後方分岐で quit を確認させるため。
2.  `handlerlist` からこのハンドラを外す。
3.  `top` と `arg` を、保存しておいた `bytecode_top` と `bytecode_dest` から復元する。
4.  現在のフレーム `bc->fp` から関数を取り出し、 `bytestr_data` 、 `vectorp` 、 `pc` を再設定する。
5.  ハンドラの `val` を `PUSH` して、 `goto op_branch` で飛び先へ進む。

正常終了のときの `Bpophandler` は、 `handlerlist = handlerlist->next` とするだけである。

コンパイラ側は `bytecomp.el:4929` （catch）と `bytecomp.el:4982-4985` （condition-case）にある。条件節ごとに `pushconditioncase` を出し、本体を抜けたら節の数だけ `pophandler` を出す。


## 訂正: なぜ setjmp の後でフレームを取り直すのか {#訂正-なぜ-setjmp-の後でフレームを取り直すのか}

`setjmp` の後で、 `top` や `pc` 、 `bytestr_data` を取り直している。最初はこれを「 `longjmp` を挟むとレジスタ上の値が不定になりうるためだろう」と推測した。

しかし、主因は別のところにあった。

関数呼び出しの高速経路（ `bytecode.c:805-817` ）は、バイトコードからバイトコードを呼ぶとき、 `goto setup_frame` で同じ `exec_byte_code` の C 活動内にフレームを積む。つまり C のスタックは増えない。

そのため、 `sys_setjmp` を呼んだ C 活動は、複数のバイトコードフレームをまとめて実行している。深い呼び出し先で `throw` されると、 `longjmp` は同じ C 活動に戻る。ところが、実行中だったバイトコードフレームはもう別のものになっている。

そこで、 `unwind_to_catch` が `set_act_rec` で `bc->fp` を push 時のフレームに戻す（ `eval.c:1459` ）。復帰側は `bc->fp->fun` から `bytestr_data` と `vectorp` を取り直す（ `bytecode.c:987-994` ）。

途中のフレームは `Breturn` を通らずに捨てられる。それでも困らないのは、 `bc_frame` が `next_stack` を使うバンプ領域だからである。 `fp` を戻すだけで解放が済む（ `bytecode.c:366-377` ）。

もう 1 つ、 `pc = bytestr_data` の直後に `goto op_branch` するのにも意味があった。

`op_branch` は `new_pc < pc` で後方分岐を判定する。先頭にリセットしておくと、この復帰は後方分岐に数えられない。結果として `quitcounter = 255` のままになり、次の本物の後方分岐で quit と GC を確認する。


## 送出側 {#送出側}


### Fthrow {#fthrow}

`Fthrow` は `eval.c:1464` にある。

内側のハンドラから外側へ `handlerlist` をたどり、 `CATCHER_ALL` なら無条件に、 `CATCHER` なら `EQ(tag)` のとき `unwind_to_catch` を呼ぶ。見つからなければ `no-catch` を signal する。

`tag` が nil のときは探索せず、そのまま `no-catch` になる。 `CONDITION_CASE` は tag が nil として扱われるためである（ `eval.c:1410` のコメント）。


### signal_or_quit {#signal-or-quit}

`signal_or_quit` は `eval.c:1943` にある。

`signal-hook-function` を呼び、 `error-conditions` を引いて、同じく `handlerlist` をたどる。ハンドラの種類ごとの動きは次のとおり。

-   `CATCHER` は飛ばす。
-   `CONDITION_CASE` は `find_handler_clause` で条件が合うか調べる。
-   `HANDLER_BIND` は、その場でハンドラ関数を呼ぶ。呼ぶ間は `SKIP_CONDITIONS` を積んで、それより下の `CONDITION_CASE` を一時的に見えなくする。呼び終えても巻き戻さず、探索を続ける。

一致するハンドラがあれば、デバッガが必要か判定してから `unwind_to_catch` に進む（ `eval.c:2063` ）。ハンドラが無いときは `top-level` に throw して、それも無ければ `fatal` である（ `eval.c:2065-2072` ）。

ここで重要なのは、 **一致するハンドラの探索中は巻き戻しをしない** ことだ。だから `handler-bind` のハンドラは、エラー発生地点のスタックを保ったまま実行できる。


## 巻き戻し {#巻き戻し}

`unwind_to_catch` は `eval.c:1422-1462` にある。

1.  `catch->nonlocal_exit` に SIGNAL か THROW の別を、 `catch->val` に値を書く。
2.  `poll_suppress_count` と `interrupt_input_blocked` を復元する。
3.  `do-while` で、 `handlerlist` が `catch` に着くまで繰り返す。各回で `unbind_to(handlerlist->pdlcount)` を呼び、 `unwind-protect` の節と dynamic binding を戻す。
4.  `lisp_eval_depth` と `act_rec` を復元し、 `sys_longjmp(catch->jmp, 1)` で飛ぶ。

ハンドラを 1 段ずつ外しながら `unbind_to` するのは、ちゃんと理由がある。コメント（ `eval.c:1413-1416` ）によると、 `unwind-protect` の節を実行する時点で、その外側の正しいハンドラ集合が有効になっている必要があるからである。

{{< mermaid >}}
flowchart LR
    A["最内ハンドラ h1 が有効なまま<br/>h1 以降の specpdl を unbind"] --> B["handlerlist を h1->next へ"]
    B --> C["h2 が有効なまま<br/>h2 以降を unbind"]
    C --> D["... catch に到達<br/>catch が有効なまま unbind"]
    D --> E["longjmp"]
{{< /mermaid >}}

この順序のおかげで、各 `unwind-protect` の後始末は、レキシカルに包んでいるハンドラが有効な状態で走る。後始末の中の `signal` も、正しい外側に届く。

`specpdl` の項目は、種類ごとに `do_one_unbind` が処理する（ `eval.c:3806` ）。 `SPECPDL_UNWIND` は `lisp_eval_depth` を復元してから関数を呼ぶ。 `SPECPDL_LET*` は動的束縛を戻す。

バイトコードの `unwind-protect` は、後始末を閉包として `record_unwind_protect(bcall0, handler)` で登録する（ `bytecode.c:1013-1020` ）。正常終了時は `unbind 1` で、非局所脱出時は `unbind_to` で、同じ項目が実行される。実体は 1 つだ。

`unbind_to` は `Vquit_flag` を一時的に退避する（ `eval.c:3942-3961` ）。後始末の途中で quit が起きないようにするためである。


## 自分で書いた関数で確かめる {#自分で書いた関数で確かめる}

次の 4 つの関数 `f1` ～ `f4` を書いて、 `byte-compile` した。 `lexical-binding` は t にしてある。

```elisp
;;; -*- lexical-binding: t -*-
(defvar log nil)
(defun g (x) (pcase x ('ok 'value) ('arith (/ 1 0)) ('wta (car 1)) ('void undefined-var-zz) ('thr (throw 'tag 'thrown)) (_ (error "other"))))
(defun cleanup () (push 'cleanup log))
(defun f1 (x) (condition-case e (g x) (arith-error 1) ((wrong-type-argument void-variable) (list (car e)))))
(defun f2 (x) (catch 'tag (g x)))
(defun f3 (x) (unwind-protect (g x) (cleanup)))
(defun f4 (x) (catch 'tag (condition-case nil (g x) (arith-error 'inner))))
(dolist (f '(f1 f2 f3 f4)) (byte-compile f))
```

`g` は引数に応じて、正常終了、 `arith-error` 、 `wrong-type-argument` 、 `void-variable` 、 `throw` 、 `error` のどれかを起こす。 `cleanup` は `log` に記録するだけの関数で、 `unwind-protect` の確認に使う。

逆アセンブルは `(disassemble (symbol-function f) (current-buffer))` で取った。


### f1: 複数節の condition-case は逆順に積まれる {#f1-複数節の-condition-case-は逆順に積まれる}

`f1` は `condition-case` を 2 節で書いたものである。

```text
f1: (condition-case e (g x) (arith-error 1) ((wrong-type-argument void-variable) (list (car e))))
 0 constant (wrong-type-argument void-variable)
 1 pushconditioncase 2      ← 最後の節を先に積む（外側）
 4 constant (arith-error)
 5 pushconditioncase 1      ← 最初の節を最後に積む（最内 = 先に検査される）
 8 constant g
 9 stack-ref 1
 10 call 1
 11 pophandler
 12 pophandler
 13 return
 14:1 pophandler            ← arith-error 節: 外側の1個を捨てる
 15 constant 1
 16 return
 17:2 car                   ← 最後の節: 捨てるハンドラなし
 18 list1
 19 return
```

バイト列は `192 49 17 0 193 49 14 0 ...` で、 `pushconditioncase` （49）のオペランドは、リトルエンディアン 2 バイトの絶対番地になっている。

`bytecomp.el:4958` は `(reverse clauses)` で積む。先頭の節が最内になるので、 `handlerlist` を内側から探す `signal` の探索で先に検査される。

復帰側（ `bytecode.c:983` ）は、飛んできたハンドラ 1 個だけを外す。残りの外側の節は、節ごとの飛び先の先頭にある `pophandler` が外す（ `bytecomp.el:5015` ）。

インタプリタ版は、同じ並びを数えて節を選ぶ（ `eval.c:1660-1664` ）。飛んできたハンドラの `next` を `oldhandlerlist` まで数え、その個数だけ `clauses` を進める。バイトコード版は飛び先の番地で選ぶので、数えない。

`:success` 節は `pushconditioncase` を積まず、本体の後ろに置かれる（ `bytecomp.el:5006` ）。

スタック深さは、ハンドラ登録時の `top` を保存し（ `bytecode.c:976` ）、復帰後に値を 1 つ積んで `depth + 1` に一致させている。コンパイラ側の `(setq byte-compile-depth (1+ depth))` （ `bytecomp.el:5013` ）と対応している。


### f4: catch の中に condition-case {#f4-catch-の中に-condition-case}

`f4` は `catch` の中に `condition-case` を入れたもので、 `catch` が外側、 `condition-case` が内側になる。

```text
0	constant  tag
1	pushcatch 3
4	constant  (arith-error)
5	pushconditioncase 1
8	constant  g
9	stack-ref 1
10	call	  1
11	pophandler
12	goto	  2
15:1	discard
16	constant  inner
17:2	pophandler
18:3	return
```

出口は 3 つある。

-   正常終了: 11 で `condition-case` を外し、 `goto` で 17 へ進み、 `catch` を外して 18 で返る。
-   `arith-error` : 15 へ復帰する。値が 1 つ積まれるので、 `discard` で捨てる（変数 `e` を使わないため）。 `inner` を積んで、17 で `catch` を外す。
-   `throw 'tag` : 18 へ直接復帰する。 `condition-case` を素通りして `catch` に届く。

基本ブロックと出口を図にすると、こうなる。点線は `longjmp` による復帰で、 `pophandler` を通らない。

{{< mermaid >}}
flowchart TD
    A["pc 0-1 pushcatch<br/>復帰先 pc 18 / 有効: catch"] --> B["pc 4-5 pushconditioncase<br/>復帰先 pc 15 / 有効: catch, cc"]
    B --> C["pc 8-10 call g<br/>有効: catch, cc"]
    C -->|"正常終了"| D["pc 11-12 pophandler<br/>cc を外して goto 17"]
    C -.->|"signal: arith-error"| E["pc 15-16 discard, inner<br/>復帰直後: cc は外済み"]
    C -.->|"throw 'tag"| G["pc 18 return<br/>ハンドラなしで終了"]
    D --> F["pc 17 pophandler<br/>catch を外す"]
    E --> F
    F --> G
{{< /mermaid >}}

`arith-error` で 15 に復帰した時点では、 `condition-case` のハンドラは C 側が外し終えている。残る `catch` は、17 の `pophandler` が外す。 `throw` で 18 に復帰した場合は、 `catch` のハンドラも C 側が外すので、 `pophandler` は要らない。


### f2 と f3 {#f2-と-f3}

`f2` は `constant tag` 、 `pushcatch 8` 、呼び出し、 `pophandler` 、 `8:return` の並びだった。 `f4` から内側の `condition-case` を除いた形である。

`f3` は `unwind-protect` の後始末を閉包として定数に持ち、 `unwind-protect` 命令で `record_unwind_protect` に登録する。正常終了の `unbind 1` も、非局所脱出の `unbind_to` も、同じ `specpdl` の項目を実行する。後始末の本体は、バイトコード上に 1 か所しかない。


### 13 経路の実行結果 {#13-経路の実行結果}

`g` の結果を変えて、13 通りの経路を実行した。

| 呼び出し   | 結果                  | 補足                              |
|--------|---------------------|---------------------------------|
| f1 に ok   | value                 |                                   |
| f1 に arith | 1                     | 1 節目                            |
| f1 に wta  | (wrong-type-argument) | 2 節目                            |
| f1 に void | (void-variable)       | 2 節目                            |
| f1 に other | 関数から脱出          | どの節にも一致しない              |
| f2 に ok   | value                 |                                   |
| f2 に thr  | thrown                |                                   |
| f2 に arith | 関数から脱出          | catch は signal を捕まえない      |
| f3 に ok   | value                 | cleanup が 1 回走る               |
| f3 に arith | 関数から脱出          | cleanup は走る                    |
| f4 に thr  | thrown                |                                   |
| f4 に arith | inner                 |                                   |
| f4 に wta  | 関数から脱出          | condition-case に一致せず catch も通り抜ける |

ソースを読んで考えたとおりの結果になった。


### signal が飛ぶまでの順序 {#signal-が飛ぶまでの順序}

`f1` に `arith` を渡したときの、C 側の呼び出しの順序を図にする。上の逆アセンブルの 1 節目（ `14:1` ）に復帰する経路である。

{{< mermaid >}}
sequenceDiagram
    participant B as exec_byte_code
    participant G as g (Fquo)
    participant S as signal_or_quit
    participant U as unwind_to_catch
    participant H as handlerlist
    B->>H: push_handler ×2 と sys_setjmp
    B->>G: call g
    G->>S: signal (arith-error)
    S->>H: 内側から検査
    H-->>S: 1 個目が一致
    S->>U: unwind_to_catch
    U->>H: unbind_to ほか
    U->>B: sys_longjmp
    Note over B: handlerlist 先頭を外す, top を bytecode_top に戻す, 値を PUSH, pc 14 へ
{{< /mermaid >}}

探索の間 `handlerlist` は巻き戻されず、 `unwind_to_catch` に入ってから巻き戻される。この順序が、前節の「一致するハンドラの探索中は巻き戻しをしない」に対応している。


## catch と condition-case の違い {#catch-と-condition-case-の違い}

`Fthrow` は `CATCHER` を `EQ(tag)` で探す。 `signal_or_quit` は `CATCHER` を `continue` で素通りする（ `eval.c:2006` ）。

両者は同じ `handlerlist` を共有している。だから `catch` の内側で `signal` しても、外側の `condition-case` が捕まえられる。逆に、 `condition-case` の内側の `throw` は、その `condition-case` には捕まらない。

また、 `throw` は `SKIP_CONDITIONS` を見ない。そのため `handler-bind` のハンドラの中でも、外側の `catch` に届く。これは `lisp.h:3816-3831` のコメントが言う「CATCHER は隠さない」に対応する。


## C から使う internal_catch との違い {#c-から使う-internal-catch-との違い}

`internal_catch` は `eval.c:1383` にある。構造は同じで、 `push_handler` → `sys_setjmp` → 関数呼び出しである。

違うのは、 `longjmp` で戻る先だ。C の呼び出し元の続きになるのが `internal_catch` で、バイトコードでは `pc` の飛び先になる。

obsolete な `Bcatch` と `Bcondition_case` は、この `internal_catch` と `internal_lisp_condition_case` を呼んでいる（ `bytecode.c:960` 、 `bytecode.c:1022` ）。


## handler-bind と SKIP_CONDITIONS の不具合候補 {#handler-bind-と-skip-conditions-の不具合候補}

ここからが、読んでいて引っかかった部分である。まず仕組みはこうなっている。

-   `handler-bind-1` は、1 つの `handler-bind` につき最大 N 個の `HANDLER_BIND` を積む（ `eval.c:1571-1576` ）。各エントリの `bytecode_dest` に、同じ `handler-bind` の外側の兄弟の数を入れる。
-   ハンドラ実行中は `SKIP_CONDITIONS(skip + bytecode_dest)` を積む（ `eval.c:2019` ）。 `signal` の探索はこれを見つけると `h` を `toskip+1` 回進め、 `handler-bind` の内側、本体、兄弟をまとめて飛ばす（ `eval.c:2027-2033` ）。
-   ところが `skip` は `for (skip = 0, ...; skip++, ...)` で、 **ループの反復回数** を数えている（ `eval.c:1996` ）。 `SKIP_CONDITIONS` で飛んだ区間は、1 反復としか数えない。

そこで疑った。ハンドラ H1 の実行中に起きた signal が、 `SKIP_CONDITIONS` を越えて外側の `handler-bind` のハンドラ H2 に届くと、 `skip` が実際の距離より小さくなる。すると H2 の実行中に積む `SKIP_CONDITIONS` の値が足りず、H2 自身を飛ばし切れないのではないか。

実験してみた。Emacs 32.0.50（2026-10-10 ビルド）で、インタプリタ版とバイトコード版の両方を試している。使った断片は次のとおり。

```elisp
;;; -*- lexical-binding: t -*-
(defun run ()
  (let ((log nil))
    (condition-case outer
        (handler-bind ((error (lambda (e) (push (cadr e) log)       ; H2 (outer)
                                (when (eq (cadr e) 'h2-err) (signal 'error '(from-h2))))))
          (condition-case _mid                                       ; 間にある catch (別条件)
              (handler-bind ((error (lambda (e)                      ; H1 (inner)
                                      (when (eq (cadr e) 'orig) (signal 'error '(h2-err))))))
                (signal 'error '(orig)))
            (arith-error 'mid)))
      (error (list 'outer-caught outer (nreverse log))))))
(message "interp:   %S" (run))
(byte-compile 'run)
(message "bytecode: %S" (run))
```

結果は、インタプリタ版もバイトコード版も `(outer-caught (error from-h2) (h2-err from-h2))` だった。対照として、H1 を外して H2 だけにした場合は、H2 が見たエラーは `(orig)` のみで期待どおりだった。

| ケース                                    | H2 が受け取ったエラー | 期待       |
|----------------------------------------|--------------|----------|
| 対照（H2 だけ。 `SKIP_CONDITIONS` の入れ子なし） | `(orig)`           | `(orig)`   |
| H1（内側）から signal し、H2（外側）が受け取って、さらに signal | `(h2-err from-h2)` | `(h2-err)` |

2 行目では、H2 が自分の中で signal したエラー `from-h2` を、H2 自身がもう一度受け取っている。

マニュアル（ `control.texi:2644-2650` ）は、ハンドラ実行中は `handler-bind` より内側のハンドラを停止するとしている。なので期待は `(h2-err)` のはずだ。既存テスト（ `eval-tests.el:331-368` ）にも、 `SKIP_CONDITIONS` が入れ子になる場合は見当たらなかった。

ただし、確度については正直に書いておく。

-   症状は再現した。しかし原因が `skip` の数え方だという点は、コードを読んでの推論である。修正して再実験まではしていない。
-   検証に使ったのは、手元にインストール済みの Emacs である。ビルド日が checkout の日と同じなので近いソースのはずだが、同一コミットかは確認していない。
-   上流へ報告するなら、同一コミットのビルドで再確認してからにしたい。

なお、検証で Emacs のソースは変更していない。


## まだ読んでいない部分 {#まだ読んでいない部分}

今回は読み切れなかったところが残っている。

-   `maybe_quit` と `quit` が `signal_or_quit` に入る経路
-   `CATCHER_ALL` を使う `internal_catch_all` （ `eval.c:1806` ）の呼び出し側
-   スレッド切替時の `handlerlist` と `bc` の扱い

このあたりは、また気が向いたら掘ってみることにする。
