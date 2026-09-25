+++
title = "macOSで「Claude環境が使っているパッケージ」を再現する"
author = ["YAMASHITA Takao"]
date = 2026-08-08T20:03:00+09:00
lastmod = 2026-09-25T22:15:17+09:00
tags = ["macOS", "Python", "Node-js", "LibreOffice"]
categories = ["Tech"]
draft = false
cover = ""
+++

Claude が Office 文書処理に使っているパッケージは、実はほぼ全て macOS でもそのまま動く（ xlwings のような Excel 本体依存とは異なるアプローチのため ）。

> [2026-08-15追記] 初稿のPowerPoint行に誤りがあったため訂正した。編集手段を `python-pptx` としていたが、実際の編集手順は unzip → XML直接編集 → zip であり、=python-pptx= はスライド複製・書式保持・SVG/EMF読み込みができないという **制約の注記** としてのみ登場する。出典: Claude環境の =/mnt/skills/public/pptx/SKILL.md=（2026-08-15時点でのセッション内で参照可能な一次資料。過去バージョンや別セッションと完全に同一である保証はない）。


## 全体像(Claude環境の実装) {#全体像--claude環境の実装}

| 形式                   | メインパッケージ                                                             | 補助                                                                                                                                            |
|----------------------|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| **Excel (.xlsx)**      | `openpyxl`                                                                   | `pandas` 、 `markitdown` 、LibreOffice(数式再計算)                                                                                              |
| **Word (.docx)**       | `docx` (npm/Node.js)                                                         | `pandoc` 、LibreOffice、 `pdftoppm` (Poppler)                                                                                                   |
| **PowerPoint (.pptx)** | `pptxgenjs` (npm、新規) / 直接XML編集(`unzip` → `ppt/slides/slideN.xml` 編集 → `zip`) | `markitdown[pptx]` 、 `Pillow` 、 `defusedxml` 、 `lxml` 、 `react` / `react-dom` / `react-icons` / `sharp` (アイコンSVG→PNG化用)、LibreOffice、 `pdftoppm` |

この構成の要点は「 **Office本体不要** 」であること。 xlwings と違い、Excel/Word/PowerPointがインストールされていないLinux/CI環境でも動く前提で組まれている。したがってmacOSでも当然インストール可能だ。

> 補足: `python-pptx` はpptx処理の公式依存リストには含まれていない。編集の主手段ではなく、「スライド複製ができない」「=text_frame.text=への代入が書式を潰す」「SVG/EMFを読み込めない」という制約を説明する文脈でのみ言及される。読み取り用途にpython-pptxを使う場面はあり得るが、その場合も `markitdown` がまず優先される。


## macOSへのインストール手順 {#macosへのインストール手順}


### 1. Python系(pip / conda環境) {#1-dot-python系--pip-conda環境}

```bash
pip install openpyxl pandas 'markitdown[pptx]' Pillow defusedxml lxml
```

Apple Siliconでも標準pipでネイティブ対応。 `lxml` のみビルド済みwheelが提供されているためコンパイル不要で入る。

> [修正] 初稿にあった `python-pptx` を依存リストから外した。編集の主手段ではなく、必須パッケージとして扱うのは実態と合わない。


### 2. Node.js系(npmパッケージ) {#2-dot-node-dot-js系--npmパッケージ}

```bash
# Node.js未導入の場合
brew install node

npm install docx pptxgenjs react react-dom react-icons sharp
```

`docx` (Word生成)、 `pptxgenjs` (PowerPoint生成)はいずれもピュアJS実装で、Office本体もLibreOfficeも不要に **文書の生成そのもの** は完結する。 `react` / `react-dom` / `react-icons` / `sharp` はpptx内のアイコン埋め込み(SVGをレンダリングしPNGにラスタライズして挿入)用途。


### 3. LibreOffice(Homebrew) {#3-dot-libreoffice--homebrew}

```bash
brew install --cask libreoffice
```

インストール後のCLI呼び出し:

```bash
/Applications/LibreOffice.app/Contents/MacOS/soffice --headless --convert-to pdf report.docx
```

PATHを通す場合:

```bash
echo 'export PATH="/Applications/LibreOffice.app/Contents/MacOS:$PATH"' >> ~/.zshrc
```

**Claude環境と同じ注意点が適用される** (前回説明の通り):

-   bare `soffice` は環境によってハングすることがある → タイムアウト付きラッパーを自作するのが安全
-   数式再計算はExcelとの完全互換ではない( `XLOOKUP` / `FILTER` / `UNIQUE` 等はスピル非対応、 `_xlfn.` プレフィックス問題あり)
-   macOS版LibreOfficeはフォントが少ないため、pptxのQAレンダリングで幅が変わる可能性


### 4. Pandoc {#4-dot-pandoc}

```bash
brew install pandoc
```


### 5. Poppler(pdftoppm) {#5-dot-poppler--pdftoppm}

```bash
brew install poppler
```


## macOS特有の注意点 {#macos特有の注意点}

| 項目                     | 内容                                                                                                                        |
|------------------------|---------------------------------------------------------------------------------------------------------------------------|
| **LibreOfficeとExcelの共存** | 同一マシンにExcel本体もある場合、 xlwings とLibreOfficeベース処理は完全に独立(相互干渉なし)。用途で使い分け可能             |
| **soffice初回起動が遅い** | 初回はプロファイル生成のため数秒〜十数秒かかる。バッチ処理の1回目だけ遅延あり、以降は高速                                   |
| **Gatekeeper警告**       | Homebrew cask版は署名済みのため通常問題なし。手動DL版で警告が出た場合は「システム設定→プライバシーとセキュリティ」で許可   |
| **並行実行の制限**       | soffice headlessは同時に複数プロセスを起動するとロック競合することがある( `--convert-to` をループで回す場合は `-env:UserInstallation=file:///tmp/lo_$$` で分離すると安全) |


## 使い分けの整理(xlwingsとの住み分け・最終まとめ) {#使い分けの整理--xlwingsとの住み分け-最終まとめ}

{{< details "xlwingsを使う場面まとめ" >}}
**xlwingsとは**：Excel本体を経由してPythonからExcelを操作するパッケージ。
openpyxl等のOffice本体不要系とは異なり、Excel本体のインストールが前提のアプローチで、macOSにも対応している。

Office本体不要のパッケージ群(openpyxl / docx(npm) / pptxgenjs / LibreOffice)とは別に、
xlwingsは以下2点でのみ必要になる。

- VBAマクロ資産をExcel本体経由で直接叩く場合
- procurement文書の最終チェックなど、Excel本体の計算エンジンでの厳密な検証が必要な場合
  (LibreOfficeの数式エンジンは`XLOOKUP`/`FILTER`/`UNIQUE`等のスピル非対応、`_xlfn.`プレフィックス問題があるため非互換)

それ以外の新規生成・バッチ処理はOffice本体不要な構成に寄せてよい。
{{< /details >}}

| 目的                                         | 推奨手段                             | 理由                                         |
|--------------------------------------------|----------------------------------|--------------------------------------------|
| VBAマクロ資産( `TransferShitekiJikou` 等)を直接叩く | **xlwings** (macOS対応)              | Excel本体経由でしか呼べない                  |
| 新規Excel/Word/PowerPoint生成、バッチ処理    | **openpyxl / docx(npm) / pptxgenjs** | Office本体不要、CI/WSLとも共有可能なコード資産にできる |
| 既存ファイルの数式再計算・PDF変換            | **LibreOffice headless**             | Excel/Word本体を起動せず軽量に処理           |
| Excel本体の計算エンジンでの厳密な検証(procurement文書の最終チェック等) | **xlwingsで実Excel**                 | LibreOfficeの数式エンジンは非互換関数がある(前述の `XLOOKUP` 等) |

自分の環境(macOS Apple Silicon / WSL Ubuntu 22.04 / Emacs中心)であれば、 **コード資産をopenpyxl/pandas/LibreOfficeベースで統一しWSL側とも共通化** し、Excel本体でしかできない処理(マクロ呼び出し、UI連携)だけ xlwings 経由でmacOS側に残す、という構成が最も再現性・保守性が高くなる。
