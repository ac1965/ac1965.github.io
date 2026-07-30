#!/usr/bin/env python3
"""
org2hugo.py — Emacs ox-hugo の `C-c C-e H A`（org-hugo-export-wim-to-md
:all-subtrees）を、Emacsを使わずPythonから再現するための変換スクリプト。

## 前提・検証範囲
all-posts.org を実際に解析して洗い出した構文のみを対象にしている:
  - ファイルレベル: #+hugo_base_dir, #+hugo_section, #+hugo_auto_set_lastmod
  - サブツリー見出し: "** [TODO/DONE] タイトル"
  - CLOSED: 行（DONE化時にorgが自動挿入するタイムスタンプ）
  - :PROPERTIES: ... :END: ドロワー内の EXPORT_FILE_NAME / EXPORT_DATE /
    EXPORT_HUGO_TAGS / EXPORT_HUGO_CATEGORIES / EXPORT_HUGO_LASTMOD /
    EXPORT_HUGO_CUSTOM_FRONT_MATTER（elispのplist文字列）
  - 本文: *bold* /italic/ =code= ~verbatim~、[[url][desc]] リンク、
    [[file:x]] ローカルファイル参照、#+begin_src、#+begin_export hugo/HUGO
    （大小どちらも可）、脚注 [fn:N] / [fn:N] 定義

## 変換エンジン
本文のOrg→Markdown変換は自前実装せず pandoc (org reader) に委譲する。
理由: Orgの本物のパーサ・強調記法・special-strings（-- → – 等、これは
pandocの独自仕様ではなく Org自体の org-export-with-special-strings に
由来する挙動）を自前で再実装するのは非現実的であり、pandocの org reader
は同じOrgパーサ規則をかなり忠実に踏襲している（本スクリプト作成時に
実データで逐一検証済み）。

## 検証根拠のアップデート
ユーザーから ox-hugo.el / ox-blackfriday.el 本体のソースコードが共有され、
以下は「未検証事項」から「ソースコードで確認済みの事実」に格上げされた:

1. **date フィールドの優先順位** (`org-hugo--get-date` 関数):
   logbook-date → CLOSED平文タイムスタンプ → EXPORT_DATE → ファイルの
   #+date、の順で優先される。CLOSEDが存在する場合は EXPORT_DATE より
   優先される。実データでは「EXPORT_DATEが空」に見えた13記事すべてに
   CLOSED行が存在しており、本物のox-hugoならそちらから date が入る。
2. **lastmod自動算出** (`org-hugo--format-date` の :hugo-lastmod 分岐):
   EXPORT_HUGO_LASTMODが空 かつ hugo_auto_set_lastmod:t の場合、
   `(org-current-time)` = **エクスポートを実行した瞬間の現在時刻**が
   使われる（gitやファイルmtimeではない）。org-hugo-suppress-lastmod-period
   のデフォルトは0.0で抑制なし。
3. **TODO状態とdraftの対応** (`org-hugo--parse-draft-state` 関数):
   TODOキーワードが存在する場合、それが org-done-keywords に含まれれば
   draft=false、含まれなければdraft=true（HUGO_DRAFTより優先）。draftキー
   は常に出力される。README.orgの設定から org-todo-keywords は
   "TODO(t) SOMEDAY(s) WAITING(w) | DONE(d) CANCELED(c@)" と判明しており、
   done-keywords = {DONE, CANCELED}。

## 既知の差異・未検証事項（要確認）
1. 上記CLOSED/lastmod/draftのタイムゾーンは、org-current-time実行時の
   Emacsのシステムタイムゾーンに依存する。ここではサイトの内容（日本語、
   ty07.net）から Asia/Tokyo (+09:00) と仮定している。異なる場合は
   --tz オプションで上書きできる。
2. Hugo側のMarkdownレンダラ(Goldmark)で footnote 拡張が有効になっている
   前提（[^N] / [^N]: ... 記法）。本物のox-hugoは "fn:" 接頭辞付きラベル
   [^fn:N] を使う（`org-blackfriday-footnote-reference` 参照）が、本
   スクリプトはpandoc由来の [^N] のままにしている。Goldmarkのfootnote
   拡張はラベルの綴りを問わないため、レンダリング結果自体は等価のはず。
3. [[file:xxx.jpg]] は pandocによって単純に ![](xxx.jpg) に変換される。
   Page Bundle方式で画像を記事ディレクトリに同梱している場合はパスの
   付け替えが必要になる可能性がある（このファイル単体では判別不能）。

## Page Bundle (Leaf Bundle) 対応
EXPORT_HUGO_BUNDLE プロパティが設定されているサブツリーだけ、Leaf Bundle
として出力する（オプトイン方式・既存記事の出力先は一切変わらない）。
ox-hugo本体の仕様 (`org-hugo--heading-get-slug`) に合わせ、実際に
Leaf Bundleにするには EXPORT_FILE_NAME を "index" にする必要がある:

  :PROPERTIES:
  :EXPORT_FILE_NAME: index
  :EXPORT_HUGO_BUNDLE: 2024-25cb-9aad
  :END:

  → content/post/2024-25cb-9aad/index.md として出力される。

本文中のローカル画像参照（Markdown の ![alt](path) と、生HTMLの
<img src="path">）のうち、リモートURLでないものは、--asset-dir で
指定したディレクトリ（未指定でもorg_file自身のディレクトリは常に
探索対象）から実ファイルを探して bundle ディレクトリ直下にコピーし、
参照パスをファイル名のみに書き換える
（`org-hugo--attachment-rewrite-maybe` の簡略再現）。
見つからない画像はコピーせず警告を出す（参照パスはそのまま残る）。

## 使い方
  python3 org2hugo.py all-posts.org --outdir ./content/post --dry-run
  python3 org2hugo.py all-posts.org --outdir ./content/post
  python3 org2hugo.py all-posts.org --outdir ./content/post --tz "+09:00"
  python3 org2hugo.py all-posts.org --outdir ./content/post \\
      --asset-dir ./images --asset-dir ~/Pictures/blog
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

TODO_KEYWORDS = ["TODO", "SOMEDAY", "WAITING", "DONE", "CANCELED"]
DONE_KEYWORDS = {"DONE", "CANCELED"}  # README.org の org-todo-keywords 設定より



@dataclass
class PostSubtree:
    raw_heading: str
    todo_state: str | None
    title: str
    heading_tags: list[str]
    properties: dict[str, str]
    closed: str | None
    body: str
    line_no: int


def strip_todo_keyword(heading_text: str) -> tuple[str | None, str]:
    for kw in TODO_KEYWORDS:
        if heading_text.startswith(kw + " "):
            return kw, heading_text[len(kw) + 1:].strip()
    return None, heading_text.strip()


HEADING_TAGS_RE = re.compile(r"\s+:([A-Za-z0-9_@#%\u3040-\u30FF\u4E00-\u9FFF:-]+):\s*$")


def strip_heading_tags(title: str) -> tuple[str, list[str]]:
    """見出し行末尾の org-tag記法 ':tag1:tag2:' を分離する。
    実データ確認済み: EXPORT_HUGO_TAGS が無い記事がこの記法だけに頼っている
    ケースが2件あった（該当記事は EXPORT_HUGO_TAGS 自体を持たない）。"""
    m = HEADING_TAGS_RE.search(title)
    if not m:
        return title, []
    tags_str = m.group(1)
    tags = [t for t in tags_str.split(":") if t]
    clean_title = title[: m.start()].rstrip()
    return clean_title, tags


def parse_properties_drawer(lines: list[str], start_idx: int) -> tuple[dict[str, str], int]:
    """lines[start_idx] が ':PROPERTIES:' である前提で解析し、
    (properties, :END: の次の行インデックス) を返す。"""
    props: dict[str, str] = {}
    i = start_idx + 1
    while i < len(lines):
        line = lines[i].strip()
        if line == ":END:":
            return props, i + 1
        m = re.match(r"^:([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if m:
            props[m.group(1)] = m.group(2).strip()
        i += 1
    raise ValueError(f"PROPERTIES drawer starting at line {start_idx} has no :END:")


def split_subtrees(text: str) -> list[PostSubtree]:
    lines = text.splitlines()
    heading_re = re.compile(r"^\*\* (?!\*)(.*)$")

    # 見出し行のインデックスを収集
    heading_idxs = [i for i, l in enumerate(lines) if heading_re.match(l)]
    subtrees: list[PostSubtree] = []

    for n, hidx in enumerate(heading_idxs):
        end_idx = heading_idxs[n + 1] if n + 1 < len(heading_idxs) else len(lines)
        heading_text = heading_re.match(lines[hidx]).group(1)
        todo_state, title = strip_todo_keyword(heading_text)
        title, heading_tags = strip_heading_tags(title)

        i = hidx + 1
        # CLOSED: / SCHEDULED: / DEADLINE: のようなplanning行。
        # CLOSEDは org-hugo--get-date で EXPORT_DATE より優先されるため値を保持する。
        closed: str | None = None
        while i < end_idx and re.match(r"^\s*(CLOSED|SCHEDULED|DEADLINE):", lines[i]):
            m = re.match(r"^\s*CLOSED:\s*\[([^\]]+)\]", lines[i])
            if m:
                closed = m.group(1)
            i += 1

        props: dict[str, str] = {}
        if i < end_idx and lines[i].strip() == ":PROPERTIES:":
            props, i = parse_properties_drawer(lines, i)

        body = "\n".join(lines[i:end_idx]).strip("\n")
        subtrees.append(
            PostSubtree(
                raw_heading=lines[hidx],
                todo_state=todo_state,
                title=title,
                heading_tags=heading_tags,
                properties=props,
                closed=closed,
                body=body,
                line_no=hidx + 1,
            )
        )
    return subtrees


def parse_elisp_plist(s: str) -> dict[str, str]:
    """':pin true :cover "custom/foo.jpg"' のような elisp plist 文字列を
    簡易パースして dict にする。値は 文字列("..") / true / false / 裸の
    トークン のいずれか。"""
    result: dict[str, str] = {}
    if not s.strip():
        return result
    token_re = re.compile(
        r':([A-Za-z_][A-Za-z0-9_-]*)\s+(".*?"|true|false|\S+)'
    )
    for m in token_re.finditer(s):
        key, val = m.group(1), m.group(2)
        result[key] = val
    return result


def toml_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


_ORG_TS_RE = re.compile(
    r"(\d{4})-(\d{2})-(\d{2})(?:\s+[A-Za-z]{2,3})?(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?"
)


def parse_org_timestamp(raw: str) -> datetime | None:
    """Org形式のタイムスタンプ文字列（CLOSED行やEXPORT_DATEの値。曜日の
    有無や秒の有無に関わらず）を解析してnaive datetimeを返す。解析でき
    なければNoneを返す。"""
    m = _ORG_TS_RE.search(raw)
    if not m:
        return None
    y, mo, d, h, mi, s = m.groups()
    return datetime(
        int(y), int(mo), int(d),
        int(h) if h else 0, int(mi) if mi else 0, int(s) if s else 0,
    )


def to_rfc3339(dt: datetime, tz: timezone) -> str:
    """org-hugo--org-date-time-to-rfc3339 と同じ書式 (%Y-%m-%dT%T%z の
    コロン挿入版) で文字列化する。"""
    dt = dt.replace(tzinfo=tz)
    return dt.strftime("%Y-%m-%dT%H:%M:%S") + dt.strftime("%z")[:3] + ":" + dt.strftime("%z")[3:]


def build_front_matter(post: PostSubtree, tz: timezone, run_time: datetime, warnings: list[str]) -> str:
    p = post.properties
    lines = ["+++"]
    lines.append(f'title = "{toml_escape(post.title)}"')

    # --- date: org-hugo--get-date の優先順位を再現 ---
    # (logbook-date は :LOGBOOK: ドロワーが実在しないこのファイルでは常にnil)
    # CLOSED平文タイムスタンプ > EXPORT_DATE > (フォールバックなし)
    export_date_raw = p.get("EXPORT_DATE", "").strip()
    date_source = None
    date_raw = None
    if post.closed:
        date_raw = post.closed
        date_source = "CLOSED"
    elif export_date_raw:
        date_raw = export_date_raw
        date_source = "EXPORT_DATE"

    if date_raw:
        dt = parse_org_timestamp(date_raw)
        if dt:
            lines.append(f'date = "{to_rfc3339(dt, tz)}"')
        else:
            warnings.append(f"[{post.title}] {date_source}={date_raw!r} を解析できませんでした")
    else:
        warnings.append(f"[{post.title}] date を決定できる値がありません（CLOSEDもEXPORT_DATEも空）")

    # --- lastmod: EXPORT_HUGO_LASTMODが空なら hugo_auto_set_lastmod:t により
    # 「エクスポート実行時刻」が入る（org-hugo--format-date の :hugo-lastmod分岐）
    lastmod_raw = p.get("EXPORT_HUGO_LASTMOD", "").strip()
    if lastmod_raw:
        dt = parse_org_timestamp(lastmod_raw)
        if dt:
            lines.append(f'lastmod = "{to_rfc3339(dt, tz)}"')
    else:
        lines.append(f'lastmod = "{to_rfc3339(run_time, tz)}"')

    # --- draft: org-hugo--parse-draft-state を再現 ---
    if post.todo_state is not None:
        draft = "false" if post.todo_state in DONE_KEYWORDS else "true"
        lines.append(f"draft = {draft}")

    tags = p.get("EXPORT_HUGO_TAGS", "").split()
    for t in post.heading_tags:
        if t not in tags:
            tags.append(t)
    if tags:
        tag_list = ", ".join(f'"{toml_escape(t)}"' for t in tags)
        lines.append(f"tags = [{tag_list}]")

    cats = p.get("EXPORT_HUGO_CATEGORIES", "").split()
    if cats:
        cat_list = ", ".join(f'"{toml_escape(c)}"' for c in cats)
        lines.append(f"categories = [{cat_list}]")

    custom = parse_elisp_plist(p.get("EXPORT_HUGO_CUSTOM_FRONT_MATTER", ""))
    for key, val in custom.items():
        if val in ("true", "false"):
            lines.append(f"{key} = {val}")
        elif val.startswith('"') and val.endswith('"'):
            lines.append(f"{key} = {val}")
        else:
            lines.append(f'{key} = "{toml_escape(val)}"')

    lines.append("+++")
    return "\n".join(lines)


def _run_pandoc(body: str, writer: str = "gfm") -> subprocess.CompletedProcess:
    return subprocess.run(
        ["pandoc", "-f", "org", "-t", writer, "--wrap=none"],
        input=body,
        capture_output=True,
        text=True,
    )


_HTML_TAG_RE = re.compile(r"(?<!\{\{)</?[a-zA-Z][a-zA-Z0-9]*(?:\s[^<>{}]*)?/?>")


def _looks_like_html_line(line: str) -> bool:
    """行がHugoショートコード呼び出し ({{< ... >}} / {{% ... %}}) ではなく、
    生のHTMLタグ（1個または複数、例: `<iframe ...></iframe>`）だけで
    構成されているかを判定する。"""
    stripped = line.strip()
    if not stripped:
        return False
    if stripped.startswith("{{<") or stripped.startswith("{{%"):
        return False
    remainder = _HTML_TAG_RE.sub("", stripped)
    return remainder.strip() == "" and _HTML_TAG_RE.search(stripped) is not None


def _wrap_raw_html_spans(content: str) -> str:
    """生HTMLタグに見える連続行を {{< rawhtml >}} ... {{< /rawhtml >}} で
    自動的に包む。フェンスコードブロック内は対象外（```で囲まれた区間は
    素通しする）。

    実データで確認した実害: <iframe>のような生HTMLをそのままMarkdown本文に
    出力すると、サイトの実設定（markup.goldmark.renderer.unsafe が false
    のまま）ではHugoが黙って <!-- raw HTML omitted --> に置き換えてしまい、
    埋め込みプレーヤーなどが跡形もなく消える（実際にHugoビルドして確認
    済み）。#+begin_export hugo ブロック内の生HTMLだけでなく、
    #+caption: を付けた画像のように pandoc自身がorgのセマンティクスから
    生HTML（<figure>等）を生成するケースも同じ実害を起こすため、
    最終的なMarkdown全体に対してこの保護を適用する。
    """
    lines = content.splitlines()
    out: list[str] = []
    i = 0
    in_fence = False
    while i < len(lines):
        if lines[i].strip().startswith("```"):
            in_fence = not in_fence
            out.append(lines[i])
            i += 1
            continue
        if not in_fence and _looks_like_html_line(lines[i]):
            j = i
            span: list[str] = []
            while j < len(lines) and (_looks_like_html_line(lines[j]) or lines[j].strip() == ""):
                span.append(lines[j])
                j += 1
            while span and span[-1].strip() == "":
                span.pop()
                j -= 1
            out.append("{{< rawhtml >}}")
            out.extend(span)
            out.append("{{< /rawhtml >}}")
            i = j
        else:
            out.append(lines[i])
            i += 1
    return "\n".join(out)


_EXPORT_BEGIN_RE = re.compile(r"^\s*#\+begin_export\s+hugo\s*$", re.IGNORECASE)
_EXPORT_END_RE = re.compile(r"^\s*#\+end_export\s*$", re.IGNORECASE)


def _extract_hugo_export_blocks(body: str) -> tuple[str, list[str]]:
    """#+begin_export hugo ... #+end_export ブロックを本文から抜き出し、
    一意なプレースホルダ行に置き換える。中身は変更せずそのまま保持する。

    なぜ事前抽出が必要か（実データで検証して発見した実例）:
    pandocに #+begin_export hugo をそのまま渡すと raw_attribute拡張により
    ```{=hugo} ... ``` という形に変換されるが、ブロックの中身自体に
    (AI会話ログの引用などとして) 手書きの ```elisp のようなMarkdown
    コードフェンスが含まれていると、外側の閉じフェンスと内側のフェンスを
    区別できず、後段の unwrap 処理が誤った位置で閉じてしまい、それ以降の
    本文が静かに破損する（バッククォートの喪失・段落の結合など）。
    org側の #+begin_export/#+end_export は行頭マーカーとして曖昧さが無い
    ため、pandocに渡す前に自前で切り出すことでこの問題を構造的に回避する。
    副産物として、pandoc側の raw_attribute 拡張が一切不要になり、
    gfmの互換性問題（バージョンにより有効/無効が分かれる）も同時に解消する。
    """
    lines = body.splitlines()
    out_lines: list[str] = []
    blocks: list[str] = []
    i = 0
    while i < len(lines):
        if _EXPORT_BEGIN_RE.match(lines[i]):
            j = i + 1
            content: list[str] = []
            while j < len(lines) and not _EXPORT_END_RE.match(lines[j]):
                content.append(lines[j])
                j += 1
            token = f"ORGHUGORAWBLOCK{len(blocks)}PLACEHOLDER"
            blocks.append("\n".join(content))
            out_lines.extend(["", token, ""])
            i = j + 1  # #+end_export の次の行へ
        else:
            out_lines.append(lines[i])
            i += 1
    return "\n".join(out_lines), blocks


def convert_body_with_pandoc(body: str) -> str:
    """pandoc経由でOrg本文をHugo向けMarkdownに変換する。

    #+begin_export hugo ブロックはpandocに渡す前に自前で抜き出し
    プレースホルダに置き換える（理由は _extract_hugo_export_blocks の
    docstring参照）。これにより pandoc呼び出しは常に素の `gfm`
    （拡張指定なし）で済み、pandocのバージョン差異にも影響されない。
    """
    preprocessed, blocks = _extract_hugo_export_blocks(body)

    result = _run_pandoc(preprocessed, "gfm")
    result.check_returncode()
    md = result.stdout

    for idx, content in enumerate(blocks):
        token = f"ORGHUGORAWBLOCK{idx}PLACEHOLDER"
        md = md.replace(token, content)

    md = _strip_pandoc_attribute_leaks(md)
    md = _wrap_raw_html_spans(md)
    md = _wrap_inline_html_markup(md)
    return md.strip() + "\n"


def _wrap_inline_html_markup(md: str) -> str:
    """行内に文字列と混在した生HTMLタグ（例: `<figcaption>本文</figcaption>`、
    `mod<sub>wsgi</sub>`）を、タグ単位で個別に rawhtml ショートコードで囲む。
    `_wrap_raw_html_spans` は行全体がHTMLタグのみの場合しか保護しないため、
    テキストとタグが同じ行に混在するケースはこちらで補う。

    実データで確認した実害:
      - `mod_wsgi` のような技術用語がorgの自動下付き変換で
        `mod<sub>wsgi</sub>` になり、unsafe=falseの実設定下でタグが
        除去されて "modwsgi" という別語になる
      - `#+caption:` 付き画像をpandocが `<figure><img/><figcaption>…
        </figcaption></figure>` に変換する際、`<figcaption>本文</figcaption>`
        のようにキャプション文字列とタグが同じ行に混在し、タグ単体の行として
        は検出できない
    フェンスコードブロック内は対象外。
    """
    lines = md.splitlines()
    out: list[str] = []
    in_fence = False
    for line in lines:
        if line.strip().startswith("```"):
            in_fence = not in_fence
            out.append(line)
            continue
        if not in_fence and not line.strip().startswith(("{{<", "{{%")) and _HTML_TAG_RE.search(line):
            line = _HTML_TAG_RE.sub(
                lambda m: "{{< rawhtml >}}" + m.group(0) + "{{< /rawhtml >}}", line
            )
        out.append(line)
    return "\n".join(out)


def _strip_pandoc_attribute_leaks(md: str) -> str:
    """generic markdown writer フォールバック時にのみ出現する、Hugo/Goldmark
    が解釈できないPandoc独自attribute記法を取り除く。gfm writerの出力には
    これらのパターンは含まれないため、no-opとして安全に適用できる。"""
    # インラインコード直後の {.verbatim} 等 (Orgの =code= に由来)
    md = re.sub(r"(`[^`\n]*`)\{\.[A-Za-z0-9_-]+\}", r"\1", md)
    # 見出し行末尾の {#auto-id}
    md = re.sub(r"^(#{1,6} .*?)\s*\{#[^}]*\}\s*$", r"\1", md, flags=re.MULTILINE)
    # フェンスコードブロックの ```{.lang key="val" ...} → ```lang
    md = re.sub(
        r'^(\s*)```\s*\{\.([A-Za-z0-9_+-]+)(?:\s+[A-Za-z0-9_-]+="[^"]*")*\s*\}\s*$',
        r"\1```\2",
        md,
        flags=re.MULTILINE,
    )
    return md


_MD_IMG_RE = re.compile(r'!\[([^\]]*)\]\(([^)\s]+)((?:\s+"[^"]*")?)\)')
_HTML_IMG_SRC_RE = re.compile(r'(<img\b[^>]*\bsrc=")([^"]+)(")')


def _is_local_path(path: str) -> bool:
    """URL（http/https等）やdata:URIではない、ローカルファイルパスらしき
    文字列かどうかを判定する。"""
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", path):
        return False
    if path.startswith("//") or path.startswith("data:"):
        return False
    return True


def _resolve_local_image(
    path: str, search_dirs: list[Path], bundle_slug: str | None = None
) -> Path | None:
    """search_dirs（org-hugo--attachment-rewrite-maybe相当の探索）の中から
    実在するファイルを探す。各search_dirに対して以下を順に試す:
      1. パスそのまま (例: ./images/foo.jpg)
      2. basenameのみ (例: foo.jpg)
      3. <search_dir>/<bundle_slug>/パスそのまま
      4. <search_dir>/<bundle_slug>/basenameのみ
    3・4は実データで確認された "assets/img/post-assets/<slug>/<file>"
    のような、記事slugごとのサブディレクトリ運用に対応するため。
    """
    clean = path.split("#", 1)[0].split("?", 1)[0]
    name = Path(clean).name
    for d in search_dirs:
        candidates = [d / clean, d / name]
        if bundle_slug:
            candidates += [d / bundle_slug / clean, d / bundle_slug / name]
        for candidate in candidates:
            if candidate.is_file():
                return candidate
    return None


def copy_bundle_images(
    md: str,
    search_dirs: list[Path],
    bundle_dir: Path,
    dry_run: bool,
    warnings: list[str],
    bundle_slug: str | None = None,
) -> str:
    """Page Bundle (Leaf Bundle) 向けに、本文中のローカル画像参照を
    bundle_dir 直下にコピーし、参照パスをファイル名だけに書き換える。

    org-hugo--attachment-rewrite-maybe の簡略版:
    - リモートURL (http/https等) は対象外、そのまま
    - 見つからない画像はコピーせず警告のみ（参照パスはそのまま残す）
    - 同名で中身の違うファイルが既にコピー先にある場合は "-1", "-2"...
      を付けて衝突を回避する
    - bundle_slug が指定されていれば、各search_dir直下だけでなく
      <search_dir>/<bundle_slug>/ 配下も探索する
    """
    copied: dict[str, str] = {}  # 元のパス文字列 -> コピー後のファイル名

    def handle(path: str) -> str:
        if not _is_local_path(path):
            return path
        if path in copied:
            return copied[path]
        src = _resolve_local_image(path, search_dirs, bundle_slug)
        if src is None:
            warnings.append(f"画像が見つからずコピーできませんでした: {path}")
            return path
        dest_name = src.name
        dest = bundle_dir / dest_name
        i = 1
        while dest.exists() and dry_run is False and dest.resolve() != src.resolve():
            dest_name = f"{src.stem}-{i}{src.suffix}"
            dest = bundle_dir / dest_name
            i += 1
        if not dry_run:
            bundle_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
        copied[path] = dest_name
        return dest_name

    def md_repl(m: re.Match) -> str:
        alt, path, title = m.group(1), m.group(2), m.group(3)
        return f"![{alt}]({handle(path)}{title})"

    def html_repl(m: re.Match) -> str:
        pre, path, post = m.group(1), m.group(2), m.group(3)
        return f"{pre}{handle(path)}{post}"

    md = _MD_IMG_RE.sub(md_repl, md)
    md = _HTML_IMG_SRC_RE.sub(html_repl, md)
    return md



def process_file(
    src_path: Path,
    outdir: Path,
    dry_run: bool,
    verbose: bool,
    tz_offset_str: str = "+09:00",
    asset_search_dirs: list[Path] | None = None,
) -> None:
    sign = 1 if tz_offset_str.startswith("+") else -1
    hh, mm = tz_offset_str.lstrip("+-").split(":")
    tz = timezone(sign * timedelta(hours=int(hh), minutes=int(mm)))
    run_time = datetime.now()

    # 画像探索先: 明示指定ディレクトリ + org_file自身の置かれているディレクトリ
    # (org-hugo--attachment-rewrite-maybe が default-directory を候補に
    #  含めるのと同じ発想)
    search_dirs = list(asset_search_dirs or []) + [src_path.parent]

    text = src_path.read_text(encoding="utf-8")
    subtrees = split_subtrees(text)

    print(f"{len(subtrees)} 件のサブツリーを検出（{src_path}）", file=sys.stderr)

    all_warnings: list[str] = []
    bundle_count = 0
    for post in subtrees:
        slug = post.properties.get("EXPORT_FILE_NAME", "").strip()
        if not slug:
            all_warnings.append(
                f"line {post.line_no}: EXPORT_FILE_NAME が無いためスキップ: {post.title}"
            )
            continue

        warnings: list[str] = []
        front_matter = build_front_matter(post, tz, run_time, warnings)
        try:
            body_md = convert_body_with_pandoc(post.body)
        except subprocess.CalledProcessError as e:
            all_warnings.append(f"{slug}: pandoc変換失敗: {e.stderr}")
            continue

        # --- Page Bundle (Leaf Bundle) 判定 ---
        # ox-hugo本体の仕様 (org-hugo--heading-get-slug) に合わせ、
        # EXPORT_HUGO_BUNDLE が設定されている記事だけをLeaf Bundle化する
        # （既存記事の出力先は一切変わらないオプトイン方式）。
        bundle = post.properties.get("EXPORT_HUGO_BUNDLE", "").strip()
        if bundle:
            if slug != "index":
                warnings.append(
                    f"EXPORT_HUGO_BUNDLE=\'{bundle}\' が設定されていますが "
                    f"EXPORT_FILE_NAME=\'{slug}\' です。ox-hugoの仕様上、"
                    f"Leaf Bundleにするには EXPORT_FILE_NAME を \'index\' に"
                    f"する必要があります（このまま index.md として出力します）"
                )
            out_path = outdir / bundle / "index.md"
            bundle_count += 1
        else:
            out_path = outdir / f"{slug}.md"

        if verbose:
            kind = f"bundle={bundle}" if bundle else "flat"
            print(f"-> {out_path}  (title={post.title!r}, todo={post.todo_state}, {kind})",
                  file=sys.stderr)

        if not dry_run:
            out_path.parent.mkdir(parents=True, exist_ok=True)

        if bundle:
            body_md = copy_bundle_images(body_md, search_dirs, out_path.parent, dry_run, warnings, bundle)

        content = front_matter + "\n\n" + body_md

        for w in warnings:
            all_warnings.append(f"{slug}: {w}")

        if not dry_run:
            out_path.write_text(content, encoding="utf-8")

    if bundle_count:
        print(f"（うち Leaf Bundle 化した記事: {bundle_count} 件）", file=sys.stderr)

    if all_warnings:
        print("\n--- warnings ---", file=sys.stderr)
        for w in all_warnings:
            print(w, file=sys.stderr)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("org_file", type=Path)
    ap.add_argument("--outdir", type=Path, default=Path("content/post"))
    ap.add_argument("--dry-run", action="store_true", help="ファイル書き込みをせず件数と警告だけ表示")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--tz", default="+09:00",
                     help="CLOSED/lastmodのタイムゾーンオフセット（既定: +09:00 = Asia/Tokyo）")
    ap.add_argument("--asset-dir", type=Path, action="append", default=[],
                     help="Page Bundle化した記事の画像を探すディレクトリ（複数指定可）。"
                          "指定が無くてもorg_file自身のディレクトリは常に探索対象。")
    args = ap.parse_args()

    process_file(args.org_file, args.outdir, args.dry_run, args.verbose, args.tz, args.asset_dir)


if __name__ == "__main__":
    main()
