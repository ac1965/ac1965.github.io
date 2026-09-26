+++
title = "Git履歴の書き換えで肝を冷やした話 ── filter-repoとClaudeで760コミットのメッセージを直す"
author = ["YAMASHITA Takao"]
date = 2026-08-09T13:36:00+09:00
lastmod = 2026-09-26T22:44:32+09:00
tags = ["Git", "Claude-Code", "filter-repo"]
categories = ["Tech"]
draft = false
cover = ""
+++

長らく `git commit -avm "Update"` でコミットしてきたツケが、.emacs.d リポジトリの760コミット分たまっていた。全部意味のないメッセージなので、いい加減直そうと思い立った。


## パイプラインを組む {#パイプラインを組む}

手作業で760件を rewrite するのは非現実的なので、Claudeに頼んで以下の3段構成のスクリプトを組んでもらった。

1.  各コミットの diff とファイル変更一覧を JSONL に抽出する
2.  Claude API に diff を投げて、Conventional Commits形式のメッセージを生成する
3.  `git filter-repo` の `--commit-callback` でメッセージを一括置換する


### 1. diffの抽出 {#1-dot-diffの抽出}

根本コミット(親を持たない最古のコミット)と、UTF-8として不正なバイト列を含むdiffの両方に対応する必要があった(詳細は後述)。

実行コマンドはこれだけ。

```bash
python3 ~/Downloads/1_extract_diffs.py --out diffs.jsonl
```


### 2. Claude APIでのメッセージ生成 {#2-dot-claude-apiでのメッセージ生成}

Conventional Commits形式で生成させ、diffから読み取れない「なぜ」は推測させない設計にした。APIエラーで落ちたコミットは、既存の出力ファイルを見て未処理分だけ再試行するレジューム方式にした。

diffと変更ファイル一覧をユーザープロンプトとして渡し、Conventional Commits形式で1件だけ返すよう指示する構成にした(システムプロンプト・スクリプト全文は末尾の追記を参照)。

まず5件だけドライランで確認した。

```bash
python3 ~/Downloads/2_generate_messages.py --in diffs.jsonl --out messages.json --dry-run --limit 5
```

出力が良さそうだったので、本番実行。

```bash
python3 ~/Downloads/2_generate_messages.py --in diffs.jsonl --out messages.json
```


### 3. filter-repoでの一括置換 {#3-dot-filter-repoでの一括置換}

`git filter-repo --commit-callback` に渡す短いスクリプト。マッピングにないコミットは元のまま維持する。

実行コマンドは以下。

```bash
REWRITE_MESSAGES_JSON="$(pwd)/messages.json" \
git filter-repo --force --commit-callback "$(cat ~/Downloads/3_rewrite_messages.py)"
```

ここまでは順調だったが、実行する過程でいくつか想定外の壁にぶつかった。


## 壁その1: 根本コミットに親がいない {#壁その1-根本コミットに親がいない}

diff抽出スクリプトが `<hash>~1` 形式で親コミットとの差分を取ろうとしていたが、リポジトリ最古の根本コミットには親が存在しないので以下のエラーで落ちた。

```bash
git diff 5c69b505ba018d85627a28035e77112a4a40ca3c~1 5c69b505ba018d85627a28035e77112a4a40ca3c
# fatal: ambiguous argument '5c69b505ba018d85627a28035e77112a4a40ca3c~1':
# unknown revision or path not in the working tree.
```

`git rev-parse --verify -q` で親の有無を先に確認し、根本コミットだけ `git diff-tree --root -p` に切り替えて対応した。


## 壁その2: UTF-8として不正なバイト列 {#壁その2-utf-8として不正なバイト列}

760件のうち300件目あたりで `UnicodeDecodeError` が発生。バイナリ差分やエンコーディングの異なるファイル名が混入していたのが原因だった。 `subprocess` の出力を `text=True` で自動デコードさせず、bytesで受け取ってから `errors`"replace"= で手動デコードするよう直して解決。


## 壁その3: APIエラーでの取りこぼし {#壁その3-apiエラーでの取りこぼし}

メッセージ生成中に何件かAPIエラーでスキップされる。最初は再実行のたびに全件やり直しになる作りだったので、既存の `messages.json` を読み込んで「まだ入っていないハッシュだけ再試行する」レジューム方式に直した。10件ごとに途中経過を保存するようにもした。


## 一番肝を冷やした瞬間 {#一番肝を冷やした瞬間}

`filter-repo --force` を実行する前に、念のためバックアップブランチを作っていた。のだが、確認したところ `ブランチ名の末尾が1文字欠けていた` 。=backup-before-rewrite= のつもりが `backup-before-rewrit` になっていた。

さらに悪いことに、=filter-repo= はデフォルトで **リポジトリ内の全ブランチ・全refを書き換え対象にする** 。つまり同一リポジトリ内に作ったバックアップブランチも、本体と一緒に書き換えられてしまっていた。以下のコマンドで確認すると、バックアップのはずのブランチが本体と全く同じコミットを指していた。

```bash
git rev-list --count HEAD
# 758
git rev-list --count backup-before-rewrite
# fatal: ambiguous argument 'backup-before-rewrite': unknown revision or path not in the working tree.
```

{{<details "この時点でのやり取りの一部(要約)">}}

```bash
git remote -v
# (出力なし。そもそもリモート未設定だと思い込んでいた)

git reflog show --all
# (出力なし)

git fsck --unreachable --lost-found
# Checking ref database: 100% (1/1), done.
# Checking object directories: 100% (256/256), done.
# Checking objects: 100% (11597/11597), done.
# Verifying commits in commit graph: 100% (762/762), done.
# (到達不能オブジェクトは0件)
```

一時は「ローカルの唯一のコピーが完全に消えた」と覚悟した。

{{</details>}}

しかし実際には `git branch -vv` で見ると、バックアップのつもりだったブランチ名の綴りが違っていただけだった。

```bash
git branch
#   backup-before-rewrit
#   feature/wsl-support
# * main

git branch -D backup-before-rewrit
```

さらにリモートを追加してpushしたところ、GitHub側には **書き換え前の本物の履歴が無傷で残っていた** ことが判明した。以前どこかのタイミングで一度pushしていたのを、すっかり忘れていただけだった。

```bash
git remote add origin git@github.com:ac1965/.emacs.d.git
git push -u origin main
# ! [rejected]        main -> main (fetch first)
# error: failed to push some refs to 'github.com:ac1965/.emacs.d.git'

git fetch origin
# From github.com:ac1965/.emacs.d
#  * [new branch]      main -> origin/main

git branch real-original-history origin/main

git log origin/main --oneline | head -20
# 9dacb62 Update
# 6202000 Update
# ...(以下Updateが並ぶ、書き換え前の本物の履歴と確定)
```

ファイルの中身が完全に一致しているかを確認してから、force pushした。

```bash
git diff main real-original-history --stat
# (出力なし = 差分ゼロ、ファイル内容は完全一致)

git push --force-with-lease origin main

git log origin/main --oneline | head -20
# 3d69e3c docs(README.org): ブログファイルを直接開く関数の追加
# 923a71e docs(design_spec): personal LayerのWSL対応とリーダーキー切替バグ修正の説明を追記
# ...(書き換え後の意味のあるメッセージに更新されているのを確認)

git branch -D real-original-history
```


## 教訓 {#教訓}

`filter-repo` のような履歴書き換え系のコマンドを使うときのバックアップは、\*同一リポジトリ内のブランチでは守り切れない\* 。書き換え対象は基本的に全ref なので、次からは以下のように別ディレクトリへの独立した clone として退避することにした。

```bash
git clone --no-hardlinks /path/to/original-repo repo-backup-$(date +%Y%m%d)
```

`--no-hardlinks` を付けるのは、通常の `git clone` はオブジェクトをハードリンク共有することがあり、元リポジトリ側で `gc --prune` が走るとバックアップ側にも影響し得るため。独立したコピーとして完全に切り離しておくのが確実だ。

結果的にファイルの実害は一切なかったが、心臓には悪かった。

もう一つ、後になって効いてきた教訓がある。 `git filter-repo` は **実行後に `.git/config` から remote セクション(`origin` など)を自動的に削除する** 。書き換え後の履歴を、古いリモートへうっかりpushしてしまう事故を防ぐための、filter-repo側の意図的な安全装置だ。この仕様を知らずに `git filter-repo` 実行直後の `git push` が `fatal: No configured push destination` で失敗し、「そもそもリモート未設定だったのか」と早合点して `git remote add origin ...` からやり直す、という遠回りを二度ほど繰り返した。ひどい時には、うろ覚えのURLで別の新しいディレクトリに素の状態で `git clone` してしまい、書き換え済みの本物の作業ディレクトリと、書き換え前の空のcloneが並存して混乱する、という事態にもなった。

対処は単純で、 **実行前に `git remote -v` の出力を控えておき、実行後は同じURLで `git remote add origin` する** ことに尽きる。

```bash
# filter-repo実行前に必ず控えておく
git remote -v

# filter-repo実行後、originが消えているので同じURLで戻す
git remote add origin <控えておいたURL>
git fetch origin
```


## APIクレジット切れとOllamaへの切り替え {#apiクレジット切れとollamaへの切り替え}

760件のメッセージ生成を `2_generate_messages.py` (Claude API版)で流している途中、Anthropicから以下の通知が届いた。

{{<details "APIクレジット切れの通知">}}
Your Claude API access is turned off
Your access to the Claude API has been disabled because your organization
'Takao's Individual Org' is out of usage credits.
{{</details>}}

760コミット分のdiffを都度APIに投げていたので、素朴に途中でクレジットを使い切ってしまった形だ。ここでローカルLLM(Ollama)への切り替えを検討した。

まず素朴に `anthropic.Anthropic()` の呼び出し部分を、Ollamaのローカルサーバー( `http://localhost:11434` )へのHTTPリクエストに差し替えた `2_generate_messages_ollama.py` を用意した。 `SYSTEM_PROMPT` や `build_user_prompt` 、レジューム(未処理分のみ再試行)・ドライラン・途中保存の仕様はClaude API版と完全に同じで、生成バックエンドだけが異なる構成にした。

```python
def generate_one(entry, host, model, timeout):
    resp = requests.post(
        f"{host}/api/generate",
        json={
            "model": model,
            "system": SYSTEM_PROMPT,
            "prompt": build_user_prompt(entry),
            "stream": False,
            "options": {
                "temperature": 0.2,  # コミットメッセージ生成なので低めにして安定させる
            },
        },
        timeout=timeout,
    )
    resp.raise_for_status()
    data = resp.json()
    return strip_code_fence(data.get("response", ""))
```

ここで気づいたのは、 `2_generate_messages_ollama.py` と `messages.json` の形式は共通なので、\*Claude APIで処理済みの分はそのまま活かして、残りをOllamaで補完するハイブリッド運用も可能\* だという点だ。両スクリプトとも `--out` で指定した `messages.json` を実行開始時に読み込み、「すでに入っているハッシュはスキップし、入っていないハッシュだけ処理する」というレジューム方式になっている。 `messages.json` の中身は `コミットハッシュ: メッセージ` という単純な形式で共通しているため、前半をClaude APIで処理し、クレジット切れ以降の残りをOllamaで処理する、という運用がそのまま成立する。

```bash
# クレジット切れまでにClaude APIで処理できた件数を確認
python3 -c "import json; print(len(json.load(open('messages.json'))))"

# 同じmessages.jsonを指定したまま、Ollama版に切り替えて残りを処理
python3 2_generate_messages_ollama.py --in diffs.jsonl --out messages.json --model qwen2.5-coder:14b
```

実行すると `resume mode: messages.json に既存N件を検出。未処理M件のみ再試行します。` のようなログが出て、Claude API分はそのまま維持しつつ残りだけがOllamaで生成される。ただし、前半(Claude API生成)と後半(Ollama生成)でメッセージの質が不揃いになり得る点は留意しておく必要がある。両者ともプロンプト自体は共通だが、モデルの能力差で要約の的確さや日本語の自然さに差が出ることはあり得るので、気になる場合は filter-repo実行前に `messages.json` を見返して手直しする運用にした。

余談だが、Ollamaのモデル選定で一つ落とし穴があった。コミュニティが公開していた `coney_/gpt-oss_claude-sonnet4.6:latest` というモデルを試したところ、中身は実際にはgpt-ossでありながら「私はAnthropicが開発したClaudeです」と自己紹介する設定になっていた。素性を偽装したモデル名だったので使用を見送り、 `qwen2.5-coder:14b` に切り替えた。

とはいえ、実際にハイブリッド運用で生成された結果を見比べると、パフォーマンスは Claude に軍配が上がる。diffの意図を汲んだ要約の的確さや日本語としての自然さで、やはり差は感じた。コストはかかるが、その分の価値はあると割り切ることにした。


## 日常運用向けのスクリプトはdotfilesへ {#日常運用向けのスクリプトはdotfilesへ}

ここまではリポジトリ全体の一括書き換えの話だったが、これはあくまで一回限りの後始末だ。今後は `Update` のようなコミットを最初から作らないようにする方が本質的なので、日常のコミット時にも Ollama でメッセージ生成を使えるよう、単発の `git diff --cached=(ステージ済みの差分)を渡してConventional Commitsメッセージを生成するスクリプト( =gen-commit-msg.sh` )を作り、[dotfiles](https://github.com/ac1965/dotfiles) に追加した。プロンプトの内容は今回の `2_generate_messages_ollama.py` と揃えてあるので、一括書き換え時と日常コミット時でメッセージのスタイルが一貫する。

```bash
#!/usr/bin/env bash
#
# gen-commit-msg.sh
#
# ステージ済みの git diff (git diff --cached) を Ollama に渡し、
# Conventional Commits 形式のコミットメッセージを生成する。
#
# 事前準備:
#   ollama serve                    (別ターミナルで起動しておく)
#   ollama pull qwen2.5-coder:14b   (初回のみ)
#
# 使い方:
#   git add -A
#   ./gen-commit-msg.sh                     # メッセージを表示するだけ
#   ./gen-commit-msg.sh --commit            # 生成したメッセージでそのままコミット
#   ./gen-commit-msg.sh --commit --edit     # 生成後、エディタで確認・編集してからコミット
#   ./gen-commit-msg.sh --model deepseek-coder-v2:16b
#   ./gen-commit-msg.sh --host http://localhost:11434
#
set -euo pipefail

MODEL="qwen2.5-coder:14b"
HOST="http://localhost:11434"
DO_COMMIT=0
DO_EDIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)  MODEL="$2"; shift 2 ;;
    --host)   HOST="$2"; shift 2 ;;
    --commit) DO_COMMIT=1; shift ;;
    --edit)   DO_EDIT=1; shift ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "[ERROR] unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# --- 前提チェック -----------------------------------------------------

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[ERROR] gitリポジトリの中で実行してください" >&2
  exit 1
fi

DIFF="$(git diff --cached)"
if [[ -z "$DIFF" ]]; then
  echo "[ERROR] ステージされた変更がありません。先に 'git add' してください" >&2
  exit 1
fi

if ! curl -s -o /dev/null -w '%{http_code}' "$HOST/api/tags" | grep -q '^200$'; then
  echo "[ERROR] $HOST に接続できません。'ollama serve' が起動しているか確認してください" >&2
  exit 1
fi

FILES_CHANGED="$(git diff --cached --name-status)"

# --- プロンプト組み立て ------------------------------------------------

SYSTEM_PROMPT='あなたはgitコミット履歴の整理を行うアシスタントです。
与えられたdiffと変更ファイル一覧から、Conventional Commits形式の
コミットメッセージを1つだけ生成してください。

ルール:
- 形式: <type>(<scope>): <summary>
  - type は feat, fix, docs, style, refactor, test, chore, perf のいずれか
  - scope は変更の主対象(ディレクトリ名やモジュール名など)。不明なら省略可
  - summary は日本語で50文字以内、命令形または体言止め
- 本文(1行空けて詳細)は、diffから読み取れる「何を変更したか」を箇条書き2〜4行で。
  「なぜ」変更したかはdiffから読み取れないため、推測で書かないこと。
- 出力はコミットメッセージ本文のみ。前置き・後書き・Markdown装飾・```などの
  コードフェンスは一切不要。説明や確認の言葉("承知しました"等)も付けないこと。'

# diffが巨大すぎるとコンテキスト長を超えるため、上限を設けて切り詰める
MAX_DIFF_CHARS=8000
if [[ ${#DIFF} -gt $MAX_DIFF_CHARS ]]; then
  DIFF="${DIFF:0:$MAX_DIFF_CHARS}
(diffは長いため途中で切り詰めています)"
fi

USER_PROMPT="変更ファイル:
${FILES_CHANGED}

diff:
${DIFF}"

# --- Ollama呼び出し -----------------------------------------------------
# jqへの依存を避けるため、リクエストJSONの組み立て・レスポンスのパースは python3 で行う

REQUEST_JSON="$(
  MODEL="$MODEL" SYSTEM_PROMPT="$SYSTEM_PROMPT" USER_PROMPT="$USER_PROMPT" python3 -c '
import json, os
print(json.dumps({
    "model": os.environ["MODEL"],
    "system": os.environ["SYSTEM_PROMPT"],
    "prompt": os.environ["USER_PROMPT"],
    "stream": False,
    "options": {"temperature": 0.2},
}))
'
)"

echo "[INFO] model=$MODEL host=$HOST でメッセージを生成中..." >&2

RESPONSE="$(curl -s -X POST "$HOST/api/generate" -d "$REQUEST_JSON")"

COMMIT_MSG="$(
  echo "$RESPONSE" | python3 -c '
import json, sys
data = json.load(sys.stdin)
text = data.get("response", "").strip()
# モデルが ```...``` で囲って返すことがあるため剥がす
if text.startswith("```"):
    lines = text.split("\n")
    if lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    text = "\n".join(lines).strip()
print(text)
'
)"

if [[ -z "$COMMIT_MSG" ]]; then
  echo "[ERROR] メッセージの生成に失敗しました。Ollamaの応答:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

echo "----------------------------------------"
echo "$COMMIT_MSG"
echo "----------------------------------------"

# --- コミット実行(任意) -------------------------------------------------

if [[ $DO_COMMIT -eq 1 ]]; then
  if [[ $DO_EDIT -eq 1 ]]; then
    git commit -e -m "$COMMIT_MSG"
  else
    git commit -m "$COMMIT_MSG"
  fi
else
  echo "[INFO] --commit を付けると、このメッセージでそのままコミットします" >&2
fi
```

使い方はこうだ。

```bash
chmod +x gen-commit-msg.sh

git add -A
./gen-commit-msg.sh                    # 生成結果を表示するだけ
./gen-commit-msg.sh --commit           # そのままコミット
./gen-commit-msg.sh --commit --edit    # エディタで確認・編集してからコミット
```

`~/bin` などPATHの通った場所に置いておけば、日常的な `git add -A && gen-commit-msg --commit --edit` の一手で、あの `Update` 地獄に逆戻りすることはなくなるはずだ。


## 追記: 正しい手順とスクリプト全文 {#appendix-correct-procedure}

本文で紆余曲折した内容を整理し、最終的に妥当だった手順とスクリプト全文を以下にまとめておく。
最大の反省点は、 **履歴書き換え専用のバックアップは、同一リポジトリ内のブランチではなく
別ディレクトリへの独立クローンで取る** こと。この教訓を反映し、元の3段構成に
`0_backup_clone.sh` を加えた0〜3の4段構成にした。

````hugo
{{< details "正しい手順(コマンド込み・まとめ)" >}}
0. バックアップクローンの作成

```bash
pip install anthropic --break-system-packages
pip install git-filter-repo --break-system-packages
export ANTHROPIC_API_KEY=sk-ant-...

chmod +x ~/Downloads/0_backup_clone.sh
~/Downloads/0_backup_clone.sh /path/to/original-repo
cd repo-backup-$(date +%Y%m%d)
```

同一リポジトリ内のブランチでは`filter-repo`の書き換え対象から逃れられない(全refが対象になる)ため、
別ディレクトリへの独立クローンを先に作る。以降の作業は**このクローン内**で行い、元リポジトリには一切触れない。

**1. diffとファイル変更一覧を抽出**

```bash
python3 ~/Downloads/1_extract_diffs.py --out diffs.jsonl
```

出力は`diffs.jsonl`(JSON Lines形式、1行1コミット)。カレントディレクトリを対象リポジトリと
みなす実装なので、必ずクローン内で実行する。マージコミットは除外され、根本コミット(親なし)は
自動的に空ツリー差分として扱われる。

必要に応じて範囲やdiffサイズも指定できる。

```bash
python3 ~/Downloads/1_extract_diffs.py --out diffs.jsonl --since HEAD~50
python3 ~/Downloads/1_extract_diffs.py --out diffs.jsonl --max-diff-chars 4000
```

**2. Claude APIでコミットメッセージを生成**

まず少数件でドライラン確認。

```bash
python3 ~/Downloads/2_generate_messages.py --in diffs.jsonl --out messages.json --dry-run --limit 5
```

問題なければ本番実行(APIエラー時は自動スキップ、再実行で未処理分のみレジューム)。

```bash
python3 ~/Downloads/2_generate_messages.py --in diffs.jsonl --out messages.json
```

**3. filter-repoで一括置換**

```bash
REWRITE_MESSAGES_JSON="$(pwd)/messages.json" \
git filter-repo --force --commit-callback "$(cat ~/Downloads/3_rewrite_messages.py)"
```

**4. 反映前に必ず差分ゼロを確認**

書き換え後、内容(メッセージ以外)が変わっていないことを元リポジトリと突き合わせる。ここは手作業だと
URLやブランチ名の打ち間違い、差分確認を飛ばして次に進んでしまう、といった事故が起きやすいので
=4_verify_and_push.sh= としてスクリプト化した(スクリプト全文は後述)。デフォルトでは検証のみ行い、
=--push= を明示しない限り絶対にpushしない。

```bash
# まず検証のみ(pushしない)
./4_verify_and_push.sh git@github.com:xxx/yyy.git main
```

差分ゼロを確認できたら、初めてforce pushする。

```bash
./4_verify_and_push.sh git@github.com:xxx/yyy.git main --push
```

**教訓の要約**

- バックアップは**別ディレクトリへの独立クローン**で取る。同一リポジトリ内のブランチは`filter-repo`の対象から逃げられない。
- `--force`の前に、バックアップの実体(クローン先ディレクトリ)を`ls`や`git rev-list --count`で目視確認する。
- push前に`git diff <old> <new> --stat`で内容の同一性を機械的に確認してから`--force-with-lease`を使う。
- `filter-repo`は実行後に`origin`リモートを自動的に削除する。実行前に`git remote -v`を控え、実行後は同じURLで`git remote add origin`し直す(この記事内の手順4はそれを踏まえた構成にしてある)。
{{< /details >}}
````

````hugo
{{< details "0_backup_clone.sh(バックアップクローン作成)" >}}
```bash
#!/usr/bin/env bash
#
# 0_backup_clone.sh
#
# filter-repo等の履歴書き換え作業用に、別ディレクトリへの独立クローンを作る。
# 同一リポジトリ内のブランチはfilter-repoの書き換え対象から逃げられないため、
# 必ず別ディレクトリのクローンとして退避する。
#
# 使い方:
#   ./0_backup_clone.sh /path/to/original-repo
#   ./0_backup_clone.sh /path/to/original-repo /path/to/dest-dir   # 出力先を指定する場合

set -euo pipefail

SRC="${1:?使い方: $0 <元リポジトリのパス> [出力先ディレクトリ]}"
DEST="${2:-repo-backup-$(date +%Y%m%d)}"

if [ -e "$DEST" ]; then
    echo "[ERROR] 出力先 '$DEST' は既に存在します。別名を指定するか削除してください。" >&2
    exit 1
fi

echo "[INFO] クローン中: $SRC -> $DEST"
git clone --no-hardlinks "$SRC" "$DEST"

cd "$DEST"
echo "[INFO] クローン完了。カレントディレクトリ: $(pwd)"
echo "[INFO] コミット数: $(git rev-list --count HEAD)"
echo "[INFO] ブランチ一覧:"
git branch -vv

echo ""
echo "[DONE] 以降の作業はこのディレクトリ内で行ってください: $DEST"
```
{{< /details >}}
````

````hugo
{{< details "1_extract_diffs.py(diff抽出)" >}}
```python
#!/usr/bin/env python3
"""
1_extract_diffs.py

対象リポジトリの全コミット(または --since 指定範囲)を走査し、
各コミットのハッシュ・現メッセージ・diff を JSONL 形式で書き出す。

使い方:
    cd /path/to/your/repo
    python3 1_extract_diffs.py --out diffs.jsonl
    python3 1_extract_diffs.py --out diffs.jsonl --since HEAD~50  # 直近50件のみ
    python3 1_extract_diffs.py --out diffs.jsonl --max-diff-chars 4000  # diffを切り詰め
"""

import argparse
import json
import subprocess
import sys


def run(cmd):
    # text=True だとUTF-8として不正なバイト列(バイナリ差分やShift-JISファイル名混入等)で
    # UnicodeDecodeError を起こして落ちるため、bytesで受け取ってerrors="replace"で手動デコードする
    result = subprocess.run(cmd, capture_output=True)
    stdout = result.stdout.decode("utf-8", errors="replace")
    stderr = result.stderr.decode("utf-8", errors="replace")
    if result.returncode != 0:
        print(f"[ERROR] command failed: {' '.join(cmd)}\n{stderr}", file=sys.stderr)
        sys.exit(1)
    return stdout


def get_commit_list(since):
    rev_range = since if since else "--all"
    # 親コミットが複数(マージコミット)は対象外にする(--no-merges)
    out = run(["git", "log", "--no-merges", "--reverse", "--pretty=format:%H", rev_range])
    return [h for h in out.splitlines() if h.strip()]


def has_parent(commit_hash):
    result = subprocess.run(
        ["git", "rev-parse", "--verify", "-q", f"{commit_hash}~1"],
        capture_output=True, text=True,
    )
    return result.returncode == 0


def get_commit_info(commit_hash, max_diff_chars):
    msg = run(["git", "log", "-1", "--pretty=format:%s%n%b", commit_hash]).strip()
    files = run(["git", "diff-tree", "--no-commit-id", "--name-status", "-r", commit_hash]).strip()
    if has_parent(commit_hash):
        diff = run(["git", "diff", f"{commit_hash}~1", commit_hash])
    else:
        # 根本コミット(親なし): 空ツリーとの差分 = 全ファイルが追加された状態
        diff = run(["git", "diff-tree", "--root", "-p", commit_hash])
    truncated = False
    if max_diff_chars and len(diff) > max_diff_chars:
        diff = diff[:max_diff_chars]
        truncated = True
    return {
        "hash": commit_hash,
        "old_message": msg,
        "files_changed": files,
        "diff": diff,
        "diff_truncated": truncated,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="出力先 JSONL ファイル")
    ap.add_argument("--since", default=None, help="git log に渡すrev-range (例: HEAD~50)。省略時は全履歴")
    ap.add_argument("--max-diff-chars", type=int, default=6000, help="diffの最大文字数(トークン節約用)")
    args = ap.parse_args()

    commits = get_commit_list(args.since)
    print(f"[INFO] {len(commits)} commits found (merge commits excluded).")

    with open(args.out, "w", encoding="utf-8") as f:
        for i, h in enumerate(commits, 1):
            info = get_commit_info(h, args.max_diff_chars)
            f.write(json.dumps(info, ensure_ascii=False) + "\n")
            if i % 50 == 0:
                print(f"[INFO] {i}/{len(commits)} processed")

    print(f"[DONE] wrote {args.out}")


if __name__ == "__main__":
    main()
```
{{< /details >}}
````

````hugo
{{< details "2_generate_messages.py(Claude APIでのメッセージ生成)" >}}
```python
#!/usr/bin/env python3
"""
2_generate_messages.py

1_extract_diffs.py の出力(diffs.jsonl)を読み、各コミットについて
Conventional Commits 形式のメッセージを Claude API で生成する。

事前準備:
    pip install anthropic --break-system-packages
    export ANTHROPIC_API_KEY=sk-ant-...

使い方(まずドライランで数件だけ確認):
    python3 2_generate_messages.py --in diffs.jsonl --out messages.json --dry-run --limit 5

問題なければ本番実行(全件):
    python3 2_generate_messages.py --in diffs.jsonl --out messages.json
"""

import argparse
import json
import os
import sys
import time

try:
    import anthropic
except ImportError:
    print("[ERROR] pip install anthropic --break-system-packages を先に実行してください", file=sys.stderr)
    sys.exit(1)


SYSTEM_PROMPT = """あなたはgitコミット履歴の整理を行うアシスタントです。
与えられたdiffと変更ファイル一覧から、Conventional Commits形式の
コミットメッセージを1つだけ生成してください。

ルール:
- 形式: <type>(<scope>): <summary>
  - type は feat, fix, docs, style, refactor, test, chore, perf のいずれか
  - scope は変更の主対象(ディレクトリ名やモジュール名など)。不明なら省略可
  - summary は日本語で50文字以内、命令形または体言止め
- 本文(1行空けて詳細)は、diffから読み取れる「何を変更したか」を箇条書き2〜4行で。
  「なぜ」変更したかはdiffから読み取れないため、推測で書かないこと。
- 出力はコミットメッセージ本文のみ。前置き・後書き・Markdown装飾は一切不要。
"""


def build_user_prompt(entry):
    return f"""変更ファイル:
{entry['files_changed']}

diff:
{entry['diff']}
{'(diffは長いため途中で切り詰めています)' if entry.get('diff_truncated') else ''}

元のメッセージ(参考、意味がないものが多い): {entry['old_message']!r}
"""


def generate_one(client, entry, model="claude-sonnet-4-6"):
    resp = client.messages.create(
        model=model,
        max_tokens=500,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": build_user_prompt(entry)}],
    )
    text_blocks = [b.text for b in resp.content if b.type == "text"]
    return "".join(text_blocks).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="infile", required=True)
    ap.add_argument("--out", dest="outfile", required=True, help="hash -> new message の JSON")
    ap.add_argument("--dry-run", action="store_true", help="ファイルに保存せず、標準出力に表示するのみ")
    ap.add_argument("--limit", type=int, default=None, help="処理件数を制限(ドライラン確認用)")
    ap.add_argument("--model", default="claude-sonnet-4-6")
    ap.add_argument(
        "--fresh", action="store_true",
        help="既存の --out ファイルを無視して全件を最初から生成し直す(デフォルトは未処理分のみのレジューム)",
    )
    args = ap.parse_args()

    with open(args.infile, encoding="utf-8") as f:
        entries = [json.loads(line) for line in f if line.strip()]

    # 既存の messages.json があれば読み込み、すでに成功済みのハッシュはスキップする
    # (= 前回APIエラーでスキップされたコミットだけが対象になる)
    results = {}
    if not args.dry_run and not args.fresh and os.path.exists(args.outfile):
        with open(args.outfile, encoding="utf-8") as f:
            results = json.load(f)
        before = len(entries)
        entries = [e for e in entries if e["hash"] not in results]
        print(
            f"[INFO] resume mode: {args.outfile} に既存 {len(results)} 件を検出。"
            f"未処理 {len(entries)}/{before} 件のみ再試行します。"
            f" (全件やり直す場合は --fresh を指定)",
            file=sys.stderr,
        )

    if args.limit:
        entries = entries[: args.limit]

    if not entries:
        print("[INFO] 未処理のコミットはありません。すべて処理済みです。")
        return

    client = anthropic.Anthropic()  # ANTHROPIC_API_KEY を環境変数から読む
    failed = []

    for i, entry in enumerate(entries, 1):
        h = entry["hash"]
        try:
            new_msg = generate_one(client, entry, model=args.model)
        except Exception as e:
            print(f"[WARN] {h[:8]} failed: {e} -- skip (元のメッセージを維持)", file=sys.stderr)
            failed.append(h)
            continue

        if args.dry_run:
            print("=" * 60)
            print(f"commit {h[:8]}")
            print(f"  旧: {entry['old_message']!r}")
            print(f"  新:\n{new_msg}")
        else:
            results[h] = new_msg

        if i % 10 == 0:
            print(f"[INFO] {i}/{len(entries)} generated", file=sys.stderr)
            if not args.dry_run:
                # 途中経過をこまめに保存(長時間実行中のクラッシュ対策)
                with open(args.outfile, "w", encoding="utf-8") as f:
                    json.dump(results, f, ensure_ascii=False, indent=2)

        time.sleep(0.3)  # レート制限対策(必要に応じ調整)

    if not args.dry_run:
        with open(args.outfile, "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        print(f"[DONE] wrote {args.outfile} ({len(results)} messages total)")
        if failed:
            print(f"[INFO] {len(failed)} 件が今回も失敗しました。同じコマンドを再実行すれば再試行されます。", file=sys.stderr)
    else:
        print(f"\n[DONE] dry-run complete ({len(entries)} entries). ファイルには保存していません。")


if __name__ == "__main__":
    main()
```
{{< /details >}}
````

````hugo
{{< details "3_rewrite_messages.py(filter-repo commit-callback)" >}}
```python
"""
3_rewrite_messages.py

git filter-repo の --commit-callback に渡すスクリプト。
messages.json (旧hash -> 新メッセージ) を読み込み、該当コミットの
メッセージを置き換える。マッピングに存在しないコミットは元のまま維持する。

事前準備:
    pip install git-filter-repo --break-system-packages
    (または https://github.com/newren/git-filter-repo をPATHに置く)

使い方:
    # 必ず 0_backup_clone.sh で別ディレクトリへ独立クローンしてから実行すること
    # (同一リポジトリ内のブランチはfilter-repoの書き換え対象から逃げられない)
    ./0_backup_clone.sh /path/to/original-repo
    cd repo-backup-YYYYMMDD

    REWRITE_MESSAGES_JSON="$(pwd)/messages.json" \
    git filter-repo --force --commit-callback "$(cat 3_rewrite_messages.py)"

    # 結果をローカルで目視確認
    git log --oneline | head -50

    # 元リポジトリと内容が完全一致することを確認してから反映
    git diff main origin/main --stat
    git push --force-with-lease
"""

import json
import os

_MESSAGES_PATH = os.environ.get("REWRITE_MESSAGES_JSON", "messages.json")

with open(_MESSAGES_PATH, encoding="utf-8") as _f:
    _messages = json.load(_f)

old_hash = commit.original_id.decode("ascii")  # noqa: F821  (filter-repoが注入する変数)

if old_hash in _messages:
    commit.message = _messages[old_hash].encode("utf-8")  # noqa: F821
# マッピングにない場合は commit.message を変更しない(元のまま)
```
{{< /details >}}
````

````hugo
{{< details "4_verify_and_push.sh(差分ゼロ確認とforce push)" >}}
```bash
#!/usr/bin/env bash
#
# 4_verify_and_push.sh
#
# git filter-repo などで履歴を書き換えた後、元リモートと「メッセージ以外の内容が
# 完全に一致しているか」を機械的に確認してから、初めて force push する。
# デフォルトでは検証のみ行い、--push を明示しない限り絶対にpushしない。
#
# 前提: filter-repo実行直後は origin リモートが自動的に削除されているため、
# このスクリプトが remote add からやり直す。
#
# 使い方:
#   cd repo-backup-YYYYMMDD   (書き換え済みの独立クローン内で実行)
#
#   # まずは検証のみ(pushしない)
#   ./4_verify_and_push.sh git@github.com:ac1965/dotfiles.git
#
#   # ブランチ名を明示(省略時は現在のブランチ)
#   ./4_verify_and_push.sh git@github.com:ac1965/dotfiles.git master
#
#   # 差分ゼロを確認できたら、実際にpushする
#   ./4_verify_and_push.sh git@github.com:ac1965/dotfiles.git master --push
#
set -euo pipefail

REMOTE_URL="${1:?使い方: $0 <remote-url> [branch] [--push]}"
shift

BRANCH=""
DO_PUSH=0

for arg in "$@"; do
  case "$arg" in
    --push) DO_PUSH=1 ;;
    *)      BRANCH="$arg" ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[ERROR] gitリポジトリの中で実行してください" >&2
  exit 1
fi

# 作業ツリーが汚れていると差分確認の意味がなくなるため先にチェック
if [[ -n "$(git status --porcelain)" ]]; then
  echo "[ERROR] 作業ツリーに未コミットの変更があります。先にcommit/stashしてください" >&2
  git status --short >&2
  exit 1
fi

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git symbolic-ref --short HEAD)"
  echo "[INFO] ブランチ未指定のため、現在のブランチ '$BRANCH' を使います" >&2
fi

# --- リモートの用意 -----------------------------------------------------
# filter-repo実行後は origin が消えているのが通例だが、
# 既にorigin以外の名前で設定されているケースも考慮し、専用のリモート名を使う

REMOTE_NAME="verify-origin"

if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  git remote remove "$REMOTE_NAME"
fi

echo "[INFO] リモート追加: $REMOTE_NAME -> $REMOTE_URL" >&2
git remote add "$REMOTE_NAME" "$REMOTE_URL"

echo "[INFO] fetch中..." >&2
if ! git fetch "$REMOTE_NAME" "$BRANCH"; then
  echo "[ERROR] fetchに失敗しました。URL・ブランチ名・認証情報(SSH鍵等)を確認してください" >&2
  git remote remove "$REMOTE_NAME"
  exit 1
fi

REMOTE_REF="$REMOTE_NAME/$BRANCH"

echo "[INFO] リモート側の直近履歴(参考):" >&2
git log "$REMOTE_REF" --oneline | head -5 >&2

# --- 差分ゼロ確認 ---------------------------------------------------------

echo "" >&2
echo "[INFO] $BRANCH と $REMOTE_REF の内容差分を確認中..." >&2

DIFF_STAT="$(git diff "$BRANCH" "$REMOTE_REF" --stat)"

if [[ -n "$DIFF_STAT" ]]; then
  echo "" >&2
  echo "[ERROR] 差分が検出されました。メッセージ以外の内容(ファイルの中身)が" >&2
  echo "        書き換え前後で一致していません。push を中止します。" >&2
  echo "" >&2
  echo "$DIFF_STAT" >&2
  echo "" >&2
  echo "[INFO] 詳細を見る場合: git diff $BRANCH $REMOTE_REF" >&2
  git remote remove "$REMOTE_NAME"
  exit 1
fi

echo "[OK] 差分ゼロを確認しました。ファイル内容は完全に一致しています。" >&2

# --- push(明示指定時のみ) -------------------------------------------------

if [[ $DO_PUSH -eq 0 ]]; then
  echo "" >&2
  echo "[INFO] --push を付けずに実行したため、pushは行いません。" >&2
  echo "[INFO] 問題なければ次のコマンドで反映してください:" >&2
  echo "       $0 $REMOTE_URL $BRANCH --push" >&2
  git remote remove "$REMOTE_NAME"
  exit 0
fi

echo "" >&2
echo "[INFO] $REMOTE_NAME/$BRANCH へ force push します..." >&2
git push --force-with-lease "$REMOTE_NAME" "$BRANCH:$BRANCH"

echo "" >&2
echo "[DONE] push完了。リモート側の履歴を確認してください:" >&2
git fetch "$REMOTE_NAME" "$BRANCH" >/dev/null 2>&1
git log "$REMOTE_REF" --oneline | head -10 >&2

# 後片付け: 検証用の一時リモート名を残すか、originとして正式採用するかは
# 呼び出し側の判断に委ねる(ここでは削除しない)
echo "" >&2
echo "[INFO] リモート '$REMOTE_NAME' はそのまま残しています。" >&2
echo "       正式にoriginとして使うなら: git remote rename $REMOTE_NAME origin" >&2
echo "       不要なら: git remote remove $REMOTE_NAME" >&2
```
{{< /details >}}
````


## 再追記(8/16): スクリプト全文 {#appendix-correct-procedure2}

「追記: 正しい手順とスクリプト全文本文」のスクリプトをパイプライン化した。

実際の実行結果を参考に残す。例はリポジトリ CodeReading が存在する前提、

````sh
cd ~/Projects/
scripts/collect_commit_msg CodeReading
[INFO] クローン中: /Users/ac1965/Projects/CodeReading -> CodeReading-backup-20260816
Cloning into 'CodeReading-backup-20260816'...
done.
[INFO] カレントディレクトリ: /Users/ac1965/Projects/CodeReading-backup-20260816
[INFO] コミット数: 3
[INFO] ブランチ一覧:
* main 2c51ec3 [origin/main] chore: .gitignoreに無視対象ファイルを追加
[STEP] diff抽出中...
[INFO] 3 commits found (merge commits excluded).
[DONE] wrote diffs.jsonl
[STEP] コミットメッセージ生成中 (model: claude-sonnet-4-6)...
[DONE] wrote messages.json (3 messages total)
[STEP] filter-repo でメッセージ書き換え中...
NOTICE: Removing 'origin' remote; see 'Why is my origin removed?'
        in the manual if you want to push back there.
        (was /Users/ac1965/Projects/CodeReading)
Parsed 3 commits
New history written in 0.04 seconds; now repacking/cleaning...
Repacking your repo and cleaning out old unneeded objects
HEAD is now at 80d255a chore(.gitignore): 無視対象ファイルを追加
Enumerating objects: 23, done.
Counting objects: 100% (23/23), done.
Delta compression using up to 10 threads
Compressing objects: 100% (18/18), done.
Writing objects: 100% (23/23), done.
Total 23 (delta 4), reused 20 (delta 4), pack-reused 0 (from 0)
Completely finished after 0.11 seconds.
[STEP] 書き換え前の履歴と比較中...
remote: Enumerating objects: 23, done.
remote: Counting objects: 100% (23/23), done.
remote: Compressing objects: 100% (18/18), done.
remote: Total 23 (delta 4), reused 20 (delta 4), pack-reused 0 (from 0)
Unpacking objects: 100% (23/23), 26.67 KiB | 26.67 MiB/s, done.
From /Users/ac1965/Projects/CodeReading
 * [new branch]      main       -> origin/main
branch 'real-original-history' set up to track 'origin/main'.
[INFO] 書き換え前後の差分(メッセージのみ変更されファイル内容は不変のはず):
[STEP] 公開用リモート 'publish' (git@github.com:ac1965/CodeReading.git) を設定中...
From github.com:ac1965/CodeReading
 * [new branch]      main       -> publish/main
[INFO] 書き換え後 HEAD: 80d255a7d8d137f1d6f14282f2a956caa2b0635a
[INFO] 直近20件:
80d255a chore(.gitignore): 無視対象ファイルを追加
7597316 fix(run.sh): macOS bash 3.2の空配列展開エラーを回避
fdaabbf chore: ドキュメント生成パイプライン一式を初期追加
[INFO] 未解決('Update'のままの)コミット数: 0
[INFO] リモート一覧 (originは比較用にクローン元 '/Users/ac1965/Projects/CodeReading' を指すよう復元済み):
origin	/Users/ac1965/Projects/CodeReading (fetch)
origin	/Users/ac1965/Projects/CodeReading (push)
publish	git@github.com:ac1965/CodeReading.git (fetch)
publish	git@github.com:ac1965/CodeReading.git (push)

[!!!] 以下は必ずこのディレクトリで実行してください: /Users/ac1965/Projects/CodeReading-backup-20260816
[!!!] 元リポジトリ '/Users/ac1965/Projects/CodeReading' はまだ書き換えられていません。
[!!!] そちらで push すると古いメッセージのまま反映されてしまいます。

[NEXT STEPS] (リモートへの force-push は副作用が大きいため、このスクリプトは自動実行しません)
  cd /Users/ac1965/Projects/CodeReading-backup-20260816

  # publishリモート(git@github.com:ac1965/CodeReading.git)は設定・fetch済みです。反映する場合:
  git push --force-with-lease publish main

  # pushが成功したら、元リポジトリ側 (/Users/ac1965/Projects/CodeReading) もこの新しい履歴に合わせる場合:
  # (書き換えでコミットハッシュが変わっているため、pullではなくresetが必要。
  #  reset --hard は未コミットの変更を破棄するので、必ずgit statusで確認してから)
  cd /Users/ac1965/Projects/CodeReading
  git status
  git fetch origin
  git reset --hard origin/main
````

````hugo
  {{< details "再追記(8/16): スクリプト全文" >}}
```bash
#!/usr/bin/env zsh
#
# collect_commit_msg.sh
#
# 元リポジトリを別ディレクトリへクローンし、diff抽出 -> コミットメッセージ生成
# -> filter-repo によるメッセージ書き換え、までを一括実行する。
#
# 使い方:
#   ./collect_commit_msg.sh <元リポジトリのパス> [出力先ディレクトリ] [オプション]
#
# オプション:
#   --ollama            Claude API の代わりにローカル Ollama でメッセージ生成する
#   --model MODEL        メッセージ生成に使うモデル名を指定する
#                         (--ollama 未指定時は claude-sonnet-4-6、指定時は qwen2.5-coder:14b がデフォルト)
#   -h, --help            このヘルプを表示する
#
# 注意:
#   git filter-repo は書き換え後にリモート(origin等)を安全のため自動的に
#   削除する。書き換え後に `git remote -v` が空でも異常ではない。

# 対話シェル(.zshrc)の設定に影響されないよう、実行前にデフォルト状態へ戻す
emulate -LR zsh
set -euo pipefail

# 未作成のディレクトリを想定しない安全策として、意図しないファイル名展開は避ける
setopt no_nomatch

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"

# 注意: zshは関数内で $0 が関数名に変わる(bashと異なる)ため、
#       スクリプト自身のパスは上で保存した SCRIPT_PATH を使う。
usage() {
    sed -n '2,19p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
}

fail() {
    print -ru2 -- "[ERROR] $1"
    exit 1
}

# --- 引数解析 -----------------------------------------------------------
# zparseopts は環境によってモジュール未整備で読み込めないことがあるため
# (実機で確認済み)、可搬性を優先して手動でパースする。
USE_OLLAMA=0
MODEL=""
typeset -a POSITIONAL
POSITIONAL=()

while (( $# > 0 )); do
    case "$1" in
        --ollama)
            USE_OLLAMA=1
            shift
            ;;
        --model)
            (( $# >= 2 )) || fail "--model にはモデル名が必要です"
            MODEL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            POSITIONAL+=("$@")
            break
            ;;
        -*)
            print -ru2 -- "[ERROR] 不明なオプション: $1"
            usage >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

(( ${#POSITIONAL[@]} >= 1 )) || {
    print -ru2 -- "[ERROR] 使い方: $SCRIPT_PATH <元リポジトリのパス> [出力先ディレクトリ] [--ollama] [--model MODEL]"
    exit 1
}

SRC="${POSITIONAL[1]}"
DEST="${POSITIONAL[2]:-}"

if [[ -z "$SRC" ]]; then
    fail "元リポジトリのパスが空です"
fi
[[ -e "$SRC" ]] || fail "元リポジトリ '$SRC' が存在しません"
SRC_ABS="${SRC:A}"
git -C "$SRC_ABS" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "'$SRC' はgitリポジトリではありません"

REPO_NAME="${SRC_ABS:t}"
DEST="${DEST:-${REPO_NAME}-backup-$(date +%Y%m%d)}"
[[ -n "$DEST" ]] || fail "出力先ディレクトリ名が空です"

if [[ "$USE_OLLAMA" -eq 1 ]]; then
    GENERATE_SCRIPT="$SCRIPT_DIR/2_generate_messages_ollama.py"
    MODEL="${MODEL:-qwen2.5-coder:14b}"
else
    GENERATE_SCRIPT="$SCRIPT_DIR/2_generate_messages.py"
    MODEL="${MODEL:-claude-sonnet-4-6}"
fi
[[ -f "$GENERATE_SCRIPT" ]] || fail "生成スクリプトが見つかりません: $GENERATE_SCRIPT"

# 各ステップの実行後に埋まる(NEXT STEPSの案内・再実行判定で使う)
DEST_ABS=""
CURRENT_BRANCH=""
PUBLISH_URL=""
DONE_MARKER=""

# --- 事前チェック ---------------------------------------------------------

check_dependencies() {
    local cmd
    for cmd in git python3 git-filter-repo; do
        command -v "$cmd" >/dev/null 2>&1 || fail "コマンドが見つかりません: $cmd"
    done
}

check_safety() {
    # DEST が SRC 自身(またはその内部)を指していないか確認する。
    # クローン先を誤って元リポジトリ内に作ると復旧が困難なため。
    local dest_parent dest_abs
    dest_parent="${DEST:h}"
    [[ -d "$dest_parent" ]] || fail "出力先の親ディレクトリが存在しません: $dest_parent"
    dest_abs="${dest_parent:A}/${DEST:t}"

    if [[ "$dest_abs" == "$SRC_ABS" || "$dest_abs" == "$SRC_ABS"/* ]]; then
        fail "出力先 '$DEST' が元リポジトリ '$SRC_ABS' の内部を指しています"
    fi
    # DEST が既に存在する場合の可否は clone_repo() 側で判定する
    # (gitリポジトリなら前回の続きから再開、そうでなければ失敗させる)。
}

# --- 各ステップ -----------------------------------------------------------

clone_repo() {
    if [[ -e "$DEST" ]]; then
        git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
            || fail "出力先 '$DEST' は既に存在しますが、gitリポジトリではありません。内容を確認するか、別名を指定/削除してください。"

        print -r -- "[INFO] 出力先 '$DEST' は既存のgitリポジトリです。前回の続きから再開します。"
        cd -- "$DEST"
        DEST_ABS="$(pwd)"
    else
        print -r -- "[INFO] クローン中: $SRC_ABS -> $DEST"
        git clone --no-hardlinks -- "$SRC_ABS" "$DEST"
        cd -- "$DEST"
        DEST_ABS="$(pwd)"
    fi

    # filter-repoによる書き換えが既に完了しているかの判定に使う
    # (.git/ 配下なのでcommitやworking treeには一切影響しない)
    DONE_MARKER="$DEST_ABS/.git/collect_commit_msg.done"

    print -r -- "[INFO] カレントディレクトリ: $DEST_ABS"
    print -r -- "[INFO] コミット数: $(git rev-list --count HEAD)"
    print -r -- "[INFO] ブランチ一覧:"
    git branch -vv
}

extract_diffs() {
    print -r -- "[STEP] diff抽出中..."
    python3 "$SCRIPT_DIR/1_extract_diffs.py" --out diffs.jsonl
}

generate_messages() {
    print -r -- "[STEP] コミットメッセージ生成中 (model: $MODEL)..."
    # 未処理分(=前回rewriteでハッシュが変わった分)だけ生成される(レジューム)
    python3 "$GENERATE_SCRIPT" --in diffs.jsonl --out messages.json --model "$MODEL"
}

rewrite_history() {
    print -r -- "[STEP] filter-repo でメッセージ書き換え中..."
    REWRITE_MESSAGES_JSON="$(pwd)/messages.json" \
        git filter-repo --force --commit-callback "$(cat -- "$SCRIPT_DIR/3_rewrite_messages.py")"

    # filter-repoは安全のためoriginを自動削除するが、書き換え前後の比較用に
    # クローン元(SRC、ローカルの退避元)を指すoriginとして復元しておく。
    # 実際の公開先(GitHub等)ではない点に注意。
    git remote add origin "$SRC_ABS"

    # main/master等ブランチ名はプロジェクトごとに異なるため決め打ちしない
    CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo master)"

    # 完了マーカー。再実行時にdiff抽出・メッセージ生成・filter-repoを
    # スキップするかどうかの判定に使う(書き換え後はハッシュが変わり
    # messages.jsonのキーと一致しなくなるため、無条件で再実行するとAPIが
    # 全コミット分無駄に呼ばれてしまう)。
    : > "$DONE_MARKER"
}

# push等の外部リモートに影響する操作はしないが、fetch/ローカルブランチ作成/diff
# はこのDEST内で完結する読み取り専用の確認作業なので自動実行する。
compare_with_original() {
    print -r -- "[STEP] 書き換え前の履歴と比較中..."
    git fetch origin
    git branch -f real-original-history "origin/${CURRENT_BRANCH}"
    print -r -- "[INFO] 書き換え前後の差分(メッセージのみ変更されファイル内容は不変のはず):"
    git diff "$CURRENT_BRANCH" real-original-history --stat
}

# remoteの追加とfetchはローカル操作でリモートには影響しないため自動実行する。
# 実際にリモートへ反映するpushだけは副作用が大きいため手動確認に残す。
setup_publish_remote() {
    PUBLISH_URL="$(git -C "$SRC_ABS" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$PUBLISH_URL" ]]; then
        print -r -- "[WARN] クローン元 '$SRC_ABS' にoriginリモートが見つからないため、publishリモートの自動設定をスキップします。"
        return
    fi

    print -r -- "[STEP] 公開用リモート 'publish' (${PUBLISH_URL}) を設定中..."
    # 前回の実行で既にpublishリモートが存在する場合にaddが失敗しないよう、
    # 存在すればURLを合わせるだけにする(冪等)。
    if git remote get-url publish >/dev/null 2>&1; then
        git remote set-url publish "$PUBLISH_URL"
    else
        git remote add publish "$PUBLISH_URL"
    fi
    # --force-with-lease はローカルが把握しているpublish/<branch>の状態を
    # 手がかりに安全性を検証するため、pushの前に必ずfetchしておく。
    git fetch publish
}

print_summary() {
    print -r -- "[INFO] 書き換え後 HEAD: $(git rev-parse HEAD)"
    print -r -- "[INFO] 直近20件:"
    git log --oneline | head -20
    local unresolved
    unresolved="$(git log --oneline | grep -c '^\S* Update$' || true)"
    print -r -- "[INFO] 未解決('Update'のままの)コミット数: $unresolved"
    print -r -- "[INFO] リモート一覧 (originは比較用にクローン元 '$SRC_ABS' を指すよう復元済み):"
    git remote -v

    print -r -- ""
    print -r -- "[!!!] 以下は必ずこのディレクトリで実行してください: $DEST_ABS"
    print -r -- "[!!!] 元リポジトリ '$SRC_ABS' はまだ書き換えられていません。"
    print -r -- "[!!!] そちらで push すると古いメッセージのまま反映されてしまいます。"
    print -r -- ""
    print -r -- "[NEXT STEPS] (リモートへの force-push は副作用が大きいため、このスクリプトは自動実行しません)"
    print -r -- "  cd $DEST_ABS"
    print -r -- ""
    if [[ -n "$PUBLISH_URL" ]]; then
        print -r -- "  # publishリモート($PUBLISH_URL)は設定・fetch済みです。反映する場合:"
        print -r -- "  git push --force-with-lease publish $CURRENT_BRANCH"
    else
        print -r -- "  # 実際のリモートへ反映する場合(公開先URLはクローン元に見つかりませんでした):"
        print -r -- "  git remote add publish <実際のリモートURL>"
        print -r -- "  git fetch publish"
        print -r -- "  git push --force-with-lease publish $CURRENT_BRANCH"
    fi
    print -r -- ""
    print -r -- "  # pushが成功したら、元リポジトリ側 ($SRC_ABS) もこの新しい履歴に合わせる場合:"
    print -r -- "  # (書き換えでコミットハッシュが変わっているため、pullではなくresetが必要。"
    print -r -- "  #  reset --hard は未コミットの変更を破棄するので、必ずgit statusで確認してから)"
    print -r -- "  cd $SRC_ABS"
    print -r -- "  git status"
    print -r -- "  git fetch origin"
    print -r -- "  git reset --hard origin/$CURRENT_BRANCH"
}

on_error() {
    local exit_code=$?
    print -ru2 -- "[ERROR] 失敗しました (行 ${LINENO})。出力先: ${DEST:-<未作成>}"
    print -ru2 -- "[ERROR] diffs.jsonl / messages.json が残っていれば、再実行時に未処理分から再開されます。"
    exit "$exit_code"
}
trap on_error ERR

check_dependencies
check_safety
clone_repo

if [[ -f "$DONE_MARKER" ]]; then
    print -r -- "[INFO] 書き換え完了マーカーを検出しました。diff抽出・メッセージ生成・filter-repoはスキップします。"
    print -r -- "[INFO] (やり直したい場合はこのDESTを削除して再実行してください)"
    CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo master)"
else
    extract_diffs
    generate_messages
    rewrite_history
fi

compare_with_original
setup_publish_remote
print_summary

```
{{< /details	 >}}
````
