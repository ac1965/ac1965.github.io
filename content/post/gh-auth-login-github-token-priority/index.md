+++
title = "gh auth login が効かないと思ったら GITHUB_TOKEN に邪魔されていた話"
author = ["YAMASHITA Takao"]
date = 2026-09-13T09:41:00+09:00
lastmod = 2026-09-21T15:24:01+09:00
tags = ["GitHub-CLI", "Git", "Shell", "Authentication"]
categories = ["Tech"]
draft = false
cover = ""
+++

いつも通り `gh auth login` を叩いたら、見慣れないメッセージで止められた。

```text
❯ gh auth login
? Where do you use GitHub? GitHub.com
The value of the GITHUB_TOKEN environment variable is being used for authentication.
To have GitHub CLI store credentials instead, first clear the value from the environment.
```

「認証情報を保存したいなら、先に環境変数をクリアしろ」と言われている。つまり `gh` は今、
ログインフローに入る前の時点で **環境変数 GITHUB_TOKEN の存在を検知し、それを認証情報として
優先使用している** ということらしい。まずは何が起きているのか、手元で確認するところから
始めた。


## 現状の確認 {#現状の確認}

```sh
echo $GITHUB_TOKEN
gh auth status
```

`echo $GITHUB_TOKEN` で値が出てくるということは、どこかのシェル設定ファイルでこの環境変数を
export している。=gh auth status= の出力を見ると、同じユーザー名 `ac1965` に対して認証情報が
二重に存在していた。

-   `ac1965=(GITHUB_TOKEN 由来・=github_pat_` プレフィックス・Active: true)
-   `ac1965=(keyring 由来・=gho_` プレフィックス・Active: false)

つまり手元には **ファイングレイン個人アクセストークン(環境変数経由)** と **OAuth トークン
(keyring 保存、過去に `gh auth login` したときのもの)** の2つが共存していて、=gh= は常に
前者を優先しているという状態だった。


## その場しのぎの対処: 環境変数を一時的に外す {#その場しのぎの対処-環境変数を一時的に外す}

今のターミナルセッションだけ通常のログインフローを試したいなら、これで十分。

```sh
unset GITHUB_TOKEN
gh auth login
```

これで `gh` が通常の認証フローに入り、macOS の認証情報ストア(keyring)へ保存できるように
なる。


## 恒久対処: シェル設定ファイルから消す {#恒久対処-シェル設定ファイルから消す}

一時しのぎで終わらせず、そもそも `GITHUB_TOKEN` を常時 export しているのをやめたいなら、
まずどこで設定しているかを探す。

```sh
grep -n "GITHUB_TOKEN" \
  ~/.zshrc \
  ~/.zprofile \
  ~/.zshenv \
  ~/.profile 2>/dev/null
```

例えば `~/.zshrc` に `export GITHUB_TOKEN=ghp_xxxxxxxxx` のような行が見つかったら、それを
削除するかコメントアウトして `source ~/.zshrc` すればいい。=echo $GITHUB_TOKEN= で何も
出なくなれば完了。


## そもそも常時 export しておくべきなのか {#そもそも常時-export-しておくべきなのか}

ここで少し立ち止まって考えた。個人の開発機で、常に `GITHUB_TOKEN` を export しっぱなしに
しておく必要は実はない。用途で分けるのが素直だと思う。

-   普段の個人開発: `gh auth login` で macOS の安全な認証情報ストアを使う
-   CI/CD や自動処理: そのプロセスを起動するときだけ `GITHUB_TOKEN` を渡す

<!--listend-->

```sh
# 普段
gh auth login

# スクリプト実行時だけ
GITHUB_TOKEN=xxxxx command
```


## 2種類のトークンの違いが気になって調べた {#2種類のトークンの違いが気になって調べた}

`gh auth status` の出力に `github_pat_` と `gho_` という異なるプレフィックスのトークンが
並んでいたので、それぞれの性質を調べてみた。


### github_pat_(ファイングレイン PAT・GITHUB_TOKEN 経由) {#github-pat--ファイングレイン-pat-github-token-経由}

ファイングレイン個人アクセストークンは **必ず有効期限が設定される** 仕様になっている。
期限日の確認方法は2通り。

-   GitHub の設定画面(<https://github.com/settings/tokens?type=beta> )でトークン一覧を見る
-   現在アクティブな認証がこのトークンなら、API レスポンスヘッダーからも直接確認できる

<!--listend-->

```sh
gh api -i user | grep -i "github-authentication-token-expiration"
```


### gho_(OAuth トークン・keyring 経由) {#gho--oauth-トークン-keyring-経由}

`gh auth login` のブラウザ認証(OAuth フロー)で発行されるトークンで、GitHub CLI 公式の
OAuth アプリに対して発行される。個人アクセストークンのような固定の有効期限は基本的に
設定されない(組織側でトークン有効期限ポリシーを強制している場合を除く)。この種別の
明確な期限確認手段については、今回調べた範囲では確証の持てる一次情報が見つからなかった。
組織のポリシーが絡む場合は「Settings &gt; Applications &gt; Authorized OAuth Apps」で該当アプリの
状態を見るのが実務的な代替手段になりそうだ。


### 更新手続きも別物 {#更新手続きも別物}

重要なのは、=gh= は `GITHUB_TOKEN` / `GH_TOKEN` が設定されている限りそれを常に優先する
ため、=gh auth login= や `gh auth refresh` を叩いても **GITHUB_TOKEN 経由の認証には
一切影響しない** という点。更新の手順もトークンの種類によって完全に別物になる。

-   GITHUB_TOKEN(github_pat\_)の更新: GitHub の設定画面でトークンを再発行し、環境変数の
    値を新しいものに上書きする。=gh auth refresh= は効かない
-   keyring(gho_)の更新: スコープ変更や期限切れ間近の更新なら `gh auth refresh=(ブラウザが
        開いて再認証)。完全に失効している場合は =gh auth login` で再ログイン

同じユーザー名の認証情報が複数表示されて紛らわしいときは、次のように切り替える。

```sh
gh auth switch --hostname github.com --user ac1965
```

ただし同名アカウントだと `--user` だけでは区別できないことがあるので、その場合は一旦
`GITHUB_TOKEN` を `unset` してから対話プロンプトで選択するのが確実だった。


## ついでに整理した: git と gh の役割分担 {#ついでに整理した-git-と-gh-の役割分担}

一連の作業をしながら、そもそも `git` と `gh` のどちらで何ができるのかが曖昧なままだった
ことに気づいたので、表にして整理した。

| 操作             | gh コマンド                      | git コマンド                          | 備考                             |
|----------------|------------------------------|-----------------------------------|--------------------------------|
| クローン         | gh repo clone owner/repo         | git clone URL                         | gh は認証済みプロトコル・資格情報を自動設定 |
| 新規リポジトリ作成 | gh repo create --private         | (該当なし)                            | git init はローカル初期化のみ    |
| ローカルを GitHub に接続 | gh repo create --source=. --push | git remote add origin → git push -u  | gh は1コマンドで完結             |
| フォーク         | gh repo fork --clone             | (該当なし)                            | GitHub 側操作のため git 単体不可 |
| リポジトリ情報表示 | gh repo view                     | git remote -v / git log               | gh は Star 数等のメタデータも取得 |
| リポジトリ一覧   | gh repo list                     | (該当なし)                            |                                  |
| リポジトリ名変更 | gh repo rename                   | git remote set-url(GitHub 側の名前は変わらない) | gh が実際の名前を変更            |
| リポジトリ削除   | gh repo delete                   | (該当なし)                            |                                  |
| フォーク元との同期 | gh repo sync                     | git fetch upstream → git merge       | gh は upstream 設定込みで1コマンド化 |
| ブランチの push  | (git に委譲)                     | git push origin branch                |                                  |
| PR 作成          | gh pr create                     | (該当なし)                            | GitHub 独自機能                  |
| PR のマージ      | gh pr merge 番号                 | git merge branch(ローカルのみ)        | gh pr merge は GitHub 上の PR をクローズ |
| Issue 作成       | gh issue create                  | (該当なし)                            |                                  |
| 認証状態確認     | gh auth status                   | (該当なし)                            |                                  |
| Git クレデンシャル設定 | gh auth setup-git                | git config credential.helper          | gh が git のクレデンシャルヘルパーに自動登録 |

ローカルの変更管理(`add=/=commit=/=branch=/=merge=/=rebase` 等)は `git` 一択で、
GitHub 側のリソース(リポジトリ本体・PR・Issue・Actions)の作成・参照・操作は `gh` が担う、
という住み分けだと理解しておけば迷わなさそうだ。


## まとめ {#まとめ}

-   `gh` は `GITHUB_TOKEN` / `GH_TOKEN` が設定されていると、それを他の認証情報源より
    常に優先する
-   `gh auth login` や `gh auth refresh` は keyring 側の認証情報にしか効かない
-   ファイングレイン PAT には必ず有効期限があり、OAuth トークン(keyring)には基本的にない
-   個人開発機では `GITHUB_TOKEN` を常時 export せず、必要なプロセスにだけ渡す方が事故が
    少ない
