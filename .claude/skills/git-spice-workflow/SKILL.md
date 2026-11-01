---
name: git-spice-workflow
description: このリポジトリ（devcontainer features集）でのgit-spiceによるコミット・ブランチ操作、Conventional Commitsのtype判断基準（PRタイトルとローカルコミットの使い分け）、プルリクエスト作成ルール、スタックPRのマージ手順を扱うスキル。「コミットして」「ブランチ作って」「PR作成して」「プルリクエスト作成」「マージして」「スタックをマージして」「git-spice」「git-spice commit」「git-spice branch」「git-spice stack」等の指示があった場合に加え、自律的にコミット作成・ブランチ操作・プルリクエスト作成・マージなどのGit操作を行う場合にも使用する。
---

# git-spiceワークフロー

git-spice使用。スタック型ブランチ管理。

## ブランチ作成ルール

- ブランチ名は`<type>/<変更内容>`形式にする（`<type>`はPRタイトルと同じConventional Commits type）。作成時点で、後述の「type判断基準」のPRタイトルの基準でtypeを決める
- 新しい作業のブランチは、未マージのスタックがあればその最上段に積む。内容が独立して見える変更（ドキュメントのみ等）でも`main`から切らない。作成前に`git-spice ls --all`で、枝分かれを含めた全ブランチから最上段を確認する
- `git-spice branch create`には`--no-commit`を付けてブランチだけを作り、変更は`git-spice commit create`でコミットする。`--insert`でスタックの途中に挿入するときは`--no-restack`も付け、上の段のrestackはコミット後に作業ツリーがきれいになってから行う

## コミット内容ルール

- コミット実行前に、ステージした変更が単一の決定・目的に絞られているか自問する。複数の独立したテーマが混ざっていたら、先に分けてコミットする
- コミットしない変更が作業ツリーに残っている間は、`git-spice commit create --no-restack`でコミットする。上に積まれたブランチは、作業ツリーがクリーンになってから`git-spice upstack restack`で1回だけrestackする
- restackで、別のworktreeでcheckoutされているブランチは、restackされずに警告が出てスキップされる。そのworktreeに未コミットの変更が無いことを確かめ、そのworktreeの中で`git-spice branch restack`する。その上のブランチは、`git-spice upstack restack`や`git-spice stack restack`をやり直してもスキップされたままなので、続けて下から順に`git-spice branch restack --branch <ブランチ>`でrestackする

## コミットメッセージ作成ルール

- すべて英語で作成。日本語は使用しない
- コミットコマンド実行前に、コミットメッセージ全文の日本語訳を提示する
- コミットは原則body付き。bodyには変更の目的や理由を記述する。typo修正等の自明な変更はbody省略可

### 規約

フォーマットは`<type>(<scope>): <subject>`（`(<scope>)`は省略可。例: `fix(rtk): skip git rewrites inside Claude Code worktrees`）。このリポジトリのCI「Validate PR title」（`.github/workflows/semantic-pull-request.yml`）が検査する規約に合わせる。

- 使えるtype: `build`、`ci`、`docs`、`feat`、`fix`、`perf`、`refactor`、`revert`、`test`、`chore`
- subjectは小文字で始め、末尾にピリオドを付けない（正規表現`^(?![A-Z]).+[^.]$`）
- 破壊的変更は`!`を付ける

### type判断基準（PRタイトル vs ローカルコミット）

本プロジェクトmainマージ=スカッシュマージ。**PRタイトル→そのままマージコミットメッセージ→CIでPRタイトル規約準拠チェック**。

- **PRタイトル:** SemVer影響type（`feat`=MINOR、`fix`=PATCH、`!`付きBREAKING CHANGE=MAJOR）のみエンドユーザー影響基準で選択（例: ユーザーが触れる機能・体験増加→`feat`、ユーザー視点不具合解消→`fix`）。`build`/`ci`/`docs`/`refactor`/`test`/`perf`/`revert`はSemVer非影響→無理にエンドユーザー影響で判断せず変更の技術的性質で選択
- **`chore`を安易な受け皿にしない:** エンドユーザー非影響だからと何でも`chore`化→type分類価値低下。技術的性質対応typeあれば、SemVer非対応typeでもそちら優先
- **個々のローカルコミット（git-spiceスタック内）:** レビュアー・将来自分向け、「コード変更が技術的に何をしているか」基準
- 同一変更でも視点差でローカルコミットとPRタイトルのtype相違あり得る（想定内、統一不要）

**破壊的変更か否か厳密検証必須。**

## プルリクエスト作成ルール

- このリポジトリにPRテンプレートは無い。本文は次の構成で簡潔に書く
  - 変更内容: マージ後に`main`へ最終的にもたらされる技術的な構成要素を、存在理由を添えて列挙する
  - テスト: 当該ブランチで実施した確認。手元のテストが無い場合はCIで確かめる旨を書く
  - 関連Issue・特記事項: 無ければ書かない
- すべて英語で作成。日本語は使用しない
- 親ブランチからの差分・当該ブランチのコミットメッセージ参考
- タイトルもコミットメッセージ規約準拠
- push済みブランチの名前のtypeがPRタイトルのtypeと食い違う場合→ブランチは改名せず、PRタイトルを正しいtypeにして、食い違いをユーザーへ報告する
- 段落内で無駄な改行をしない
- **変更内容: 実装プロセスでなく最終状態記述。** 時系列的開発経緯 禁止
- 記述内容に対象ブランチ以外の変更が含まれていないか確認する

## mainへの追従

- スタックを最新の`main`の上に載せ直すときは、作業ツリーがクリーンな状態で、`git-spice repo sync`でローカルの`main`を更新し、`git-spice stack restack --branch <スタック内のブランチ>`でそのスタックだけをrestackする。`git-spice repo restack`は他のスタックもrestackするので使わない
- 別のworktreeでcheckoutされているブランチとその上のブランチは、「コミット内容ルール」のとおりrestackする
- pushは、スタック内のブランチをcheckoutした状態で`git-spice stack submit --update-only`で行い、PRの無いブランチにPRを作らない

## スタックPRのマージ

### 前提

- mainへのマージはsquash mergeを使う（このリポジトリは他の方式も許可しているが、直近の`main`はsquash mergeの履歴）。マージ後、headブランチは自動削除され（`deleteBranchOnMerge`が有効）、1つ上のPRのマージ先はGitHubがmainへ付け替える
- 作業ツリーがクリーンで、スタックの全ブランチのローカルとリモートが一致していること。未コミットの変更がある場合は、push前に`git stash push -u`で退避し、push後に戻す
- マージ前の確かめ: このリポジトリには手元のテストが無い。GitHub の CI がすべて成功していること（`gh pr checks <N>` の全項目が pass）

### 1本ごとの手順

1. `git-spice ls`で一番下のブランチとPR番号`<N>`を特定し、`gh pr view <N> --json baseRefName,headRefOid,mergeStateStatus`で次を確認する
   - マージ先がmain
   - head SHAがローカルのブランチと一致
   - `mergeStateStatus`が`CLEAN`（CI実行中なら`CLEAN`になるまで待つ）
   - 次のブランチと一番下のブランチとの差分を控える
2. `gh pr merge <N> --squash --match-head-commit <手順1のhead SHA>`でマージする
   - `--subject`・`--body`・`--delete-branch`は付けない
3. `git-spice repo sync --restack=aboves`でローカルへ反映し、次を確認する
   - 出力に`#<N> was merged`と`<次のブランチ>: restacked on main`がある
   - mainの最新コミットが`<PRタイトル> (#<N>)`
   - 次のブランチの`main`との差分が、手順1で控えた差分と一致する
4. `git-spice branch submit --branch <次のブランチ>`でpushし、次のPRのマージ先がmain、head SHAがローカルと一致、`mergeStateStatus`が`CLEAN`になったことを確認する
5. 手順1へ戻る。最後のPRをマージしたら「完了時の確認」へ進む

- `--restack=upstack`・`git-spice stack submit`等で、スタック全体を毎回restack・pushしない

### 完了時の確認

- マージしたブランチがローカル・リモートとも残っていない
- `git-spice log short --all`で`needs restack`・`needs push`が表示されない。表示される場合は、`git-spice repo restack`と、該当スタックでの`git-spice stack submit`を実行し、再度確認する

### 異常時

- 確認項目が1つでも想定と異なれば、その場で止めてユーザーへ報告する
