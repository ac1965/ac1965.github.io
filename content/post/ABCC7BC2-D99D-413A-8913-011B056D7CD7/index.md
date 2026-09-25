+++
title = "keyboxdのSQLiteエラーからTouch ID復号まで――GPGまわりを一日かけて掘った話"
author = ["YAMASHITA Takao"]
date = 2026-07-25T10:09:00+09:00
lastmod = 2026-09-25T22:15:17+09:00
tags = ["Emacs", "GnuPG", "macOS", "TouchID", "GPG"]
categories = ["Tech"]
draft = false
+++

## ある朝、.authinfo.gpg が開けなくなった {#ある朝-dot-authinfo-dot-gpg-が開けなくなった}

きっかけは単純だった。Emacsでいつも通り `~/.authinfo.gpg` を開こうとしたら、こんなエラーが出た。

```text
Error while decrypting with "/opt/homebrew/bin/gpg":
gpg: keydb_search failed: I/O error during SQL operation
gpg: encrypted with ECDH key, ID D8E725A8316E4066
gpg: key "AA2C51685BA2F0416C2FEB16BEBE9731AC8B2551" not found: I/O error during SQL operation
gpg: all values passed to '--default-key' ignored
gpg: keydb_search failed: I/O error during SQL operation
gpg: public key decryption failed: No secret key
gpg: decryption failed: No secret key
```

"I/O error during SQL operation" ってなんだ。GPGでSQLのエラーが出るのを初めて見た。


## keyboxdとSQLite、そしてGnuPG 2.5系という沼 {#keyboxdとsqlite-そしてgnupg-2-dot-5系という沼}

調べていくと、GnuPGは2.4系くらいから公開鍵の管理を `keyboxd` というデーモン経由でSQLiteバックエンド(`pubring.db`)に持たせる方式に移行しつつある。自分の環境は `brew list --versions gnupg` で確認したところ `2.5.21` 。これはdevel版ではなく、Homebrew-coreが配布している現行の安定版らしい（GnuPGは2025年にバージョニング体系を変えていて、2.5.x系列がメインラインになっている）。

一つずつ潰していった。

-   ロックを握っているプロセスがいないか（ `lsof` → 何も出ない）
-   `pubring.db` のパーミッションは `600` で問題なし
-   `xattr -l` で見ると `com.apple.provenance` だけ。怪しいquarantine属性ではない
-   `sqlite3 pubring.db "PRAGMA integrity_check;"` → `ok`
-   ボリュームはローカルAPFS。ネットワークドライブでも同期ストレージでもない

ファイルは壊れていない。ロックもない。パーミッションも正常。それでも "I/O error during SQL operation" が出続ける。

こういうとき一番早いのは、原因を完全に特定することより「迂回する」ことだったりする。


## pubring.kbxへの切り戻しで即解決 {#pubring-dot-kbxへの切り戻しで即解決}

keyboxdのSQLiteパスをそもそも通らないようにする。レガシー形式の `pubring.kbx` に戻すだけだ。

```bash
gpgconf --kill all
sed -i '' '/^use-keyboxd$/d' ~/.gnupg/common.conf
mv ~/.gnupg/public-keys.d ~/.gnupg/public-keys.d.broken.$(date +%Y%m%d)
gpgconf --kill all
gpg --list-keys
```

```text
gpg: keybox '/Users/ac1965/.gnupg/pubring.kbx' が作成されました
```

これで "I/O error during SQL operation" は綺麗さっぱり消えた。もちろん公開鍵は空っぽになるので、その後は秘密鍵（ `private-keys-v1.d` は無傷で残っている）に対応する公開鍵を再インポートする作業が必要になる。

まだ枯れきっていないバックエンドを無理に使い続けるより、確実に動く方に倒す。今回はそれが正解だった。


## ついでにTouch ID化した {#ついでにtouch-id化した}

.authinfo.gpg を開くたびにパスフレーズを打つのも面倒だったので、この機会に `pinentry-touchid` を導入してTouch ID認証に置き換えた。 `gpg-agent.conf` はこうなっている。

```cfg
allow-loopback-pinentry
default-cache-ttl 1800
# allow-emacs-pinentry
pinentry-program /opt/homebrew/bin/pinentry-touchid
```

`allow-emacs-pinentry` はあえてコメントアウトしてある。有効にするとEmacsのミニバッファ入力が優先されるケースがあり、Touch ID方式と競合するからだ。


### 共通鍵暗号のファイルをTouch IDで復号するときの注意 {#共通鍵暗号のファイルをtouch-idで復号するときの注意}

ここでちょっと引っかかった。 `pinentry-touchid` は「公開鍵の秘密鍵」と「共通鍵（パスフレーズだけの `gpg -c`  ）暗号化ファイル」を区別しない。仕組みを見ると、gpg-agentが渡してくる cache-id をキーにmacOSのKeychain（サービス名 `GnuPG` ）を検索しているだけで、キー種別には興味がない。

つまり共通鍵暗号のファイルにTouch IDを使うと、 **そのファイルを復号するためのパスフレーズそのものがKeychainに保存される** ことになる。Touch IDは「読み出しのゲート」であって、パスフレーズがSecure Enclaveに守られるわけではない。公式READMEにもそう明記されていた。

はじめは「Touch ID＝安全」と直感的に思ってしまいそうになるが、それは半分正しくて半分違う。以下、実際に運用する上で気をつけていること。

-   `default-cache-ttl` はgpg-agent自身のメモリキャッシュにしか効かない。Keychainのエントリは手動削除しない限り無期限に残る
-   `gpg --symmetric` は暗号化のたびにS2K saltが変わるので、同じパスフレーズでもファイルが変わるとcache-idも変わり、Keychain未登録扱いになって再度手動入力が必要になることがある。だから毎回中身が変わるファイルより、頻繁に開く1つのファイル（ `.authinfo.gpg` みたいな）に使うのが現実的
-   どうしても気になる場合は、共通鍵暗号ではなく公開鍵暗号に切り替えるのが筋がいい。その場合Touch IDがガードするのは「秘密鍵へのアクセス」であって、秘密鍵自体は `~/.gnupg/private-keys-v1.d` にファイルとして存在する。パスフレーズをKeychainに丸ごと預けるのとは性質が違う

結論として、今回は復号頻度の高い `.authinfo.gpg` 用途だと割り切ってTouch ID化した。重要度の高いファイルは引き続き公開鍵方式のままにしてある。


### Keychainへの登録、実は pinentry-mac の仕事 {#keychainへの登録-実は-pinentry-mac-の仕事}

ここでちょっと訂正しておきたいことがある。「Touch IDでパスフレーズをKeychainに保存する」と書いたが、正確には `pinentry-touchid` 自身はKeychainへの書き込みを一切やっていない。書き込み・登録の実体は `pinentry-mac` が持っていて、 `pinentry-touchid` はそこに登録済みのエントリをTouch ID認証つきで読みに行くだけ、という役割分担になっている（公式READMEに明記されている）。

なので実際にKeychainへ登録する一連の流れはこうなる。

```bash
# 事前に、pinentry-macにKeychain保存を許可しておく
defaults write org.gpgtools.common UseKeychain -bool yes
```

その状態でパスフレーズ入力が必要な操作（ `gpg -as -` でも実際の復号でもいい）を行うと、 `pinentry-mac` のダイアログに「Save in Keychain」のチェックボックスが出る。ここにチェックを入れると、続けてmacOSのログインパスワード入力を求められることがある。これは `pinentry-mac` や `pinentry-touchid` がこのエントリにアクセスする権限をOSから正式に認可してもらうためのもので、ここで **Always Allow** を選んでおく。

さらに `pinentry-touchid` 側でも初回のTouch ID認証時に、同じように「このエントリへのアクセスを許可するか」を聞かれることがある。README曰く：

> If a password entry is found but is not "owned" by the pinentry-touchid program after the successful authentication with Touch ID, a normal password will be shown. [...] In this dialog click Always allow after entering the password.

ここでも Always Allow。二段階の認可を経て、ようやく完全にTouch IDだけで完結するようになる。

登録できたかどうかはCLIから確認できる。

```bash
security find-generic-password -s 'GnuPG'
```

属性の一覧が返れば登録済み。何も見つからなければ次のようなエラーになる。

```text
security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.
```

パスフレーズの権限が完全に `pinentry-touchid` 側に移った後は、 `pinentry-mac` 側からの新規書き込みを止めておくとよい。README側も推奨している設定。

```bash
defaults write org.gpgtools.common DisableKeychain -bool yes
```

エントリを消したいとき（パスフレーズをローテートした時など）は、これも `security` コマンド一発。

```bash
security delete-generic-password -s 'GnuPG' -a '<アカウント名>'
```

`<アカウント名>` は `find-generic-password -s 'GnuPG'` で返ってくる属性一覧の中の `acct` の値。gpg-agentが渡すcache-idがベースになっているので、事前に確認してから使う。

「Touch IDが魔法のように守ってくれている」わけではなく、中身は地道な `pinentry-mac` ↔ Keychain ↔ `pinentry-touchid` の権限委譲の積み重ねだと分かると、何かあったときの切り分けもしやすくなる。

-   `gpg-agent` まわりの "I/O error during SQL operation" は、keyboxd/SQLiteバックエンド固有の問題である可能性が高い。ロック・パーミッション・xattr・ファイルシステムをひと通り疑ってダメなら、素直に `pubring.kbx` に切り戻すのが早い
-   `pinentry-touchid` は便利だが、内部的には「Touch IDでKeychainのエントリを読み出しているだけ」という理解を持って使う。特に共通鍵暗号ファイルに使う場合は、パスフレーズ自体がKeychainに常駐する点を踏まえて、対象ファイルの重要度を見極める

トラブルシューティングは大体こういう順番で潰していくと迷わない。

1.  ロック（他プロセスが握っていないか）
2.  パーミッション・所有者
3.  ファイル自体の整合性（今回なら `PRAGMA integrity_check` ）
4.  環境要因（xattr、ファイルシステム、同期ストレージ）
5.  それでもダメならバックエンド自体を疑う

同じ沼にハマった人の参考になれば。
