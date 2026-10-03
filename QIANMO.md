<!-- Copyright 2026 Qianmo AgentNest Team -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# 阡陌 Codex（qmcode）fork 说明

本仓库是 [openai/codex](https://github.com/openai/codex) 的 fork，供阡陌 AgentNest 的本地—云端接力（P17）使用。文档里称「阡陌 Codex」，二进制名 `qmcode`。

| 项 | 内容 |
|---|---|
| 上游基线 | 标签 `rust-v0.158.0`（提交 `064c6b8c73`） |
| 阡陌改动线 | `qianmo/main`；上游 `main` 分支保持纯镜像 |
| 许可 | 上游 `LICENSE`、`NOTICE` 原样保留。按 Apache-2.0 第 4(b) 条，每个改过的源文件头部有一行 `Modified by Qianmo AgentNest Team (2026): …`。insta 快照文件（`.snap`）的格式放不下注释行，它们的改动记在下面第 2 节 |

## 1. 与官方 Codex 同机共存

| 项 | 官方 Codex | qmcode |
|---|---|---|
| 二进制 | `codex` | `qmcode` |
| `--version` 输出 | `codex-cli <版本>` | `qmcode <版本>` |
| 状态目录 | `~/.codex` | `~/.qmcode` |
| 指定状态目录的环境变量 | `CODEX_HOME` | `QMCODE_HOME`（qmcode 不读 `CODEX_HOME`） |
| Unix 系统级配置 | `/etc/codex/{config,requirements,managed_config}.toml` | `/etc/qmcode/` 下同名文件 |
| `app-server daemon` 自动更新 | 默认开 | 默认关 |
| 登录凭据 | 默认存到 `$CODEX_HOME/auth.json` | 默认存到 `~/.qmcode/auth.json` |

登录凭据的存储方式由 `cli_auth_credentials_store` 决定，`config/defaults.toml` 默认是 `file`。改用 `keyring` 或 `auto` 时，系统钥匙串条目的 service 是 `Codex Auth`，account 是 `cli|<状态目录规范路径的 sha256 前 16 位>`（`login/src/auth/storage.rs` 的 `compute_store_key`）。状态目录不同，条目就不同，所以钥匙串模式也不会和官方 Codex 共用条目。`secrets` 后端同理：account 是 `secrets|<同一哈希>`，密文文件放在状态目录下。

## 2. 逐文件改动清单

路径都相对于 `codex-rs/`。

| 文件 | 改了什么 | 为什么 |
|---|---|---|
| `cli/Cargo.toml` | `[[bin]] name` 和 `default-run` 由 `codex` 改为 `qmcode`；`logs_client` 不动 | 二进制与官方 `codex` 同机共存 |
| `cli/src/main.rs` | clap 的 `name`、`bin_name`、`override_usage` 和 `completion` 子命令生成补全脚本时用的命令名改为 `qmcode`；`plugin marketplace` 帮助用例期望的用法行改为 `qmcode`；新增 `--version` 输出用例 | `--version` 输出 `qmcode <版本>`，能与官方 `codex-cli` 区分；帮助文本与实际命令一致；`qmcode completion` 不能生成注册到 `codex` 上的补全，否则会覆盖官方补全；clap 把父命令名传给子命令，子命令上写死的 `bin_name = "codex plugin …"` 在帮助里不生效 |
| `cli/src/snapshots/qmcode__*.snap`（4 个）、`cli/src/doctor/snapshots/qmcode__*.snap`（7 个） | 由 `codex__*.snap` 改名；`qmcode__exec_server_args_tests__exec_server_help_documents_remote_options.snap` 里的 `Usage: codex exec-server` 改为 `Usage: qmcode exec-server` | insta 快照文件名的前缀是 crate 名，二进制改名后 crate 名随之变为 `qmcode`；用法行跟随 `bin_name` |
| `utils/home-dir/src/lib.rs` | `find_codex_home()` 读 `QMCODE_HOME`，默认 `~/.qmcode`；错误信息同步；新增用例确认设了 `CODEX_HOME` 也不影响结果 | 状态目录隔离的唯一入口：会话、sqlite、日志、arg0 临时目录、daemon socket、`.env`、登录凭据都由它派生 |
| `config/src/loader/mod.rs` | Unix 系统级 `config.toml`、`requirements.toml` 改到 `/etc/qmcode/` | 同机装了官方企业配置时，qmcode 不读它 |
| `config/src/loader/layer_io.rs` | 旧版托管配置 `managed_config.toml` 改到 `/etc/qmcode/` | 同上 |
| `app-server-daemon/src/settings.rs` | `auto_update_enabled` 的结构体默认值和反序列化默认值都改为 `false` | 托管 daemon 开着自动更新时会从上游地址装回官方包并切过去运行 |
| `app-server-daemon/src/settings_tests.rs` | 遥测标签用例按默认关闭更新期望值；新增「没有设置文件时自动更新为关」用例 | 跟随默认值 |
| `app-server-daemon/src/update_loop_tests.rs` | 两条测更新器行为的用例在开头显式写入 `autoUpdateEnabled: true` | 这两条原先靠默认开启；改后仍覆盖「开启时」的更新器路径 |
| `tui/src/external_editor.rs` | 外部编辑器草稿目录的默认家目录回退由 `~/.codex` 改为 `~/.qmcode` | 这是写入路径：沙箱策略下状态目录不可用时会回退到这里建 `editor/` 临时文件，不改会写进官方目录 |
| `tui/src/external_editor_tests.rs` | 「默认家目录可写时退到工作区」用例把 `~/.qmcode` 设为可写（原为 `~/.codex`） | 跟随上面的回退目录；不改的话，HOME 不在 `/tmp` 下时用例失败，还会在真实 `~/.qmcode/editor` 建目录 |
| `tui/src/app/tests.rs` | 「编辑器目录可写时拒绝」快照用例的回退目录改为 `~/.qmcode` | 同上 |
| `tui/src/status/helpers.rs` | 状态页 AGENTS.md 摘要用例的全局路径与内联快照改为 `~/.qmcode/AGENTS.md` | 显示路径跟随状态目录 |
| `Cargo.lock` | 158 个工作区 crate 的 `version` 由 `0.0.0` 改为 `0.158.0`，其余不变 | 上游发行提交只改 `Cargo.toml` 的版本号，不提交这一步就无法 `--locked` 构建。这是 cargo 生成的文件，不加文件头：cargo 下次非 `--locked` 改写时会把注释行去掉 |
| `../QIANMO.md`（新增） | 本文件 | 改动清单、合并步骤、构建方法 |
| `../qianmo/build-linux.sh`（新增） | Linux 原生构建脚本 | 见第 6 节 |
| `../.github/workflows/qianmo-build-linux.yml`（新增） | 手动触发的 Linux x86_64 构建 workflow | 见第 6 节 |

## 3. 刻意不改的部分

- app-server 的方法名与通知名、`originator` 头的值 `codex_cli_rs`、rollout 文件格式与文件名、项目级 `.codex/` 目录、`AGENTS.md`。
- 注入子进程或由用户设置的 `CODEX_*` 环境变量，例如 `CODEX_THREAD_ID`、`CODEX_SQLITE_HOME`。注意：用户若全局导出了 `CODEX_SQLITE_HOME`，qmcode 也会读它，两边的 sqlite 状态会放到同一目录。默认不设时，sqlite 放在各自的状态目录里。
- 下列位置仍直接读 `CODEX_HOME` 或写死 `.codex`，判定为不影响隔离，未改：

| 位置 | 行为 | 判定 |
|---|---|---|
| `config/src/codex_home_symlink.rs` | 开了 `allow_symlinked_codex_home` 时，用 `CODEX_HOME` 保留软链接形式的家目录路径 | 只在它与 qmcode 状态目录规范化后相同时才采用，不会越界。代价：`QMCODE_HOME` 是软链接时不保留软链接路径 |
| `cli/src/doctor/disk.rs` | 解析状态目录失败时，退回用 `CODEX_HOME` 量磁盘剩余空间 | 只统计剩余空间，不读写内容 |
| `cli/src/bin/logs_client.rs` | `--codex-home` 缺省时取 `CODEX_HOME` | 开发用小工具，不随 `qmcode` 发布，按要求不动 |
| `app-server/src/request_processors/feedback_doctor_report.rs` | 给 `doctor` 子进程设 `CODEX_HOME` | 子进程是 qmcode，会继承父进程的 `QMCODE_HOME`；属于注入子进程的 `CODEX_*` 变量 |
| `app-server-daemon/src/update_loop.rs` | 调官方安装脚本时设 `CODEX_HOME` 为 qmcode 状态目录 | 只在开启自动更新或手动 `app-server daemon update` 时发生，默认已关 |
| `arg0/src/lib.rs` | `~/.qmcode/.env` 不允许设置 `CODEX_*` 变量 | `QMCODE_HOME` 不在过滤范围内；只在用户自己往 `.env` 写它时有影响 |
| `ext/skills`、`core-plugins` | 读 `~/.agents/skills`、`~/.cache/codex-runtimes` | 跨工具共享的只读目录，不是 `~/.codex` |

## 4. 已知未适配（合并、跑测试前必读）

- **上游集成测试**（按 `utils/cargo-bin` 的查找逻辑推断，未实跑）：`cli/tests`、`core/tests`、`app-server/tests`、`tui/tests`、`rmcp-client/tests` 里大量用 `cargo_bin("codex")` 找二进制，并给子进程设 `CODEX_HOME` 做隔离。fork 后 cargo 不再设 `CARGO_BIN_EXE_codex`，这些用例会在起进程前失败；但若 `target/debug/` 下还留着改名前编出的 `codex`，用例会跑到那个旧二进制。不要只把 `cargo_bin("codex")` 改成 `qmcode`：环境变量不跟着改的话，子进程会落到真实的 `~/.qmcode`。`test-binary-support` 在测试启动时只设 `CODEX_HOME`，`core`、`exec-server` 的测试因此会在 `HOME` 下建 `.qmcode/tmp/arg0`（按代码推断；`codex-tui` 单测实测会在 `HOME` 下建 `.qmcode/tmp/arg0`）。这些集成测试不在合并门禁内（第 5 节），跑的话按第 5 节把 `HOME` 指到临时目录。
- **Windows**：`%ProgramData%\OpenAI\Codex` 下的系统级配置、Windows 沙箱安装助手出错时按 `CODEX_HOME` 写日志、daemon 在 Windows 上转绝对路径的环境变量列表，都未改。M1 不出 Windows 产物。
- **macOS 托管偏好**：MDM 域 `com.openai.codex` 未改，qmcode 仍会读管理员强制下发的官方 Codex 配置。
- **Bazel**：`BUILD.bazel` 仍按 `codex` 命名。本 fork 只支持 cargo 构建。
- **升级入口**：`qmcode update` 和 TUI 的升级提示仍指向官方包（npm `@openai/codex`、Homebrew、`chatgpt.com/codex/install.sh`）。P17.3 处理，见第 9 节。
- **上游 workflow**：fork 上 Actions 已启用，上游的 29 个 workflow 都处于启用状态。push `qianmo/*` 分支不会触发任何上游 workflow（分支过滤只有 `main` 和 `**full-ci**`，分支名不要带 `full-ci`）；但下列操作会触发：push fork 的 `main`（`blocking-ci`、`postmerge-ci`）、fork 内开任何 PR（`blocking-ci`、`v8-canary`）、推 `rust-v*.*.*` 标签（`rust-release`，跑完还会经 `workflow_run` 带起 `python-sdk-cli-release`；`rusty-v8-v*`、`codex-zsh-v*` 同理）。`cla`、`issue-*`、`close-stale-contributor-prs`、`python-sdk-release` 有 `openai/codex` 仓库判断，在 fork 上触发后跳过。runner 写成 `${{ github.event.repository.name }}-*` 的 job 在 fork 上解析为 `qianmo-codex-*` 自定义 runner，和 `macos-15-xlarge` 的 job 一样开跑即失败，不会排队（2026-09-29 push `main` 的两次运行实测如此）。**不要把上游标签推到 fork**；构建脚本也不依赖标签。是否在 fork 的 Actions 设置里停用这些 workflow，待负责人定（第 9 节）。
- **用户钥匙串与插件服务**：`user-verification` 按账号区分钥匙串标签，锁文件在 `~/Library/Application Support/com.openai.codex/`。MCP OAuth 默认存钥匙串（`mcp_oauth_credentials_store = "auto"`），非 Windows 上默认走 direct 后端，条目 service 是 `Codex MCP Credentials`，account 由 MCP 服务器名和 URL 的哈希构成，不含状态目录。两边配置了同名、同 URL 的 MCP 服务器，或登录同一账号时，会读到同一条目。ChatGPT/API 登录凭据不受影响。

## 5. 合并上游

1. 只合并上游**发行标签**（`rust-vX.Y.Z`），不跟 `main`：
   ```sh
   git fetch upstream --tags
   git checkout qianmo/main
   git merge --no-ff rust-vX.Y.Z
   ```
   上游标签只留在本地：推送到 fork 时只推分支，不用 `--tags`、`--follow-tags`（推 `rust-v*` 标签会触发上游发布 workflow，见第 4 节）。
2. 解决冲突。`cli/src/main.rs`、TUI 的 slash 命令文件每个发行周期都可能改到，冲突一般是枚举和 match 各加一行。`core`、`tui/src/chatwidget.rs`、`tui/src/app/event_dispatch.rs` 不碰。
3. 复查上游新代码：重新搜 `"CODEX_HOME"`、`join(".codex")`、`/etc/codex`、`bin_name = "codex`，按第 3 节口径逐条判定。cli 二进制若新增了 `codex__*.snap` 快照，改名为 `qmcode__*.snap`。
4. `Cargo.lock`：本 fork 提交了工作区版本号，上游发行标签上的 `Cargo.lock` 里工作区 crate 仍是 `0.0.0`。工作区版本行只有本 fork 一侧改过，合并通常不在这些行上冲突，合并结果仍是旧版本号，所以**合并后无论有无冲突都要重写一次**：
   - `Cargo.lock` 有冲突时，先取上游一侧：`git checkout --theirs codex-rs/Cargo.lock`；
   - 在 `codex-rs/` 下跑 `cargo update --workspace`，它只改写工作区成员的条目，不动依赖；
   - 核对 `git diff codex-rs/Cargo.lock` 只有工作区 `version` 行变化（旧版本号或 `0.0.0` → 新版本号），然后单独提交；
   - 之后 `cargo build --locked` 必须能通过。

   2026-10-03 在源码导出副本上验证过：标签版 `Cargo.lock` 跑 `cargo update --workspace` 后，与本 fork 提交的 `Cargo.lock` 逐字节一致；把工作区版本改成 `0.159.0` 再跑，差异恰好是 158 行版本号。
5. 合并门禁：跑下面这组测试（它取代计划 §4「`cargo test` 覆盖改过的 crate」的说法；上游 `cli/tests`、`core/tests` 等集成测试不适配，也不作为门禁）。`HOME` 指到一个**不在 `/tmp`、`$TMPDIR` 下**的空目录（外部编辑器用例的沙箱策略允许写临时目录，HOME 放在那里会让用例假过）；栈大小与上游 CI 一致：
   ```sh
   cd codex-rs
   mkdir -p target/qianmo-test-home
   export HOME="$PWD/target/qianmo-test-home" CARGO_HOME=<原 ~/.cargo> RUSTUP_HOME=<原 ~/.rustup> RUST_MIN_STACK=8388608
   cargo test -p codex-utils-home-dir -p codex-config -p codex-app-server-daemon
   cargo test -p codex-cli --bin qmcode
   cargo test -p codex-tui --lib
   ```
   跑完 `target/qianmo-test-home` 下应只有 `.qmcode`。在 `rust-v0.158.0` 上，`codex-tui` 有 40 条用例失败：
   - 39 条是快照差异：快照是在上游 `main`（工作区版本 `0.0.0`）上录的，发行标签把版本改成了 `0.158.0`，差异只有版本号和它引起的排版宽度；
   - 1 条是 insta 报「Insta does not allow inline snapshot assertions in loops」，落在 `tui/src/app/tests/safety_buffering.rs` 里共用 `interrupt_after_inactive_steer` 的两条用例之一，哪条失败每次不同。该文件与上游标签一致。

   判据是失败数不增加，快照差异仍只含版本号。失败的快照用例会在源码树里留下未跟踪的 `*.snap.new` 和 `.*.pending-snap`，核对完删掉，不要提交。
6. 复查上游 workflow：合并可能带进新的 workflow 文件，或改动已有文件的触发条件。按第 4 节「上游 workflow」一条重新核对，不要推上游标签。
7. 重跑 P17.2 第 3、5 项探针；重新出 Linux 产物（第 6 节）。
8. 在第 8 节记一行：日期、标签、冲突文件、耗时。

## 6. 构建

本机（macOS，自测用，不作为发布产物；macOS 上不交叉编译 Linux）：

```sh
cd codex-rs
cargo build --release --bin qmcode
# 产物：codex-rs/target/release/qmcode
```

Linux 发布产物**以 GitHub Actions 为主**：workflow `.github/workflows/qianmo-build-linux.yml` 有两种触发：push 任何 `qianmo/build/**` 分支（不需要改默认分支，日常用这个），或手动 `workflow_dispatch`（可选输入 `ref`，要求文件在默认分支上）。它在 `ubuntu-24.04`（x86_64）上执行：

1. checkout（不保留凭据）；
2. 用 apt 装 `build-essential pkg-config libssl-dev`；
3. 用 rustup 装 `rust-toolchain.toml` 钉的工具链；
4. 执行 `qianmo/build-linux.sh`；
5. 用 `actions/upload-artifact` 上传产物、`.sha256`、`.buildinfo`（含编译秒数）、`.build.log`，保留 30 天；构建失败时单独上传日志。

第三方 action 都钉完整的提交 sha。触发方式：

```sh
gh workflow run qianmo-build-linux.yml --repo sweetcornna/qianmo-codex --ref <分支> [-f ref=<分支/标签/提交>]
```

日常触发：`git push origin <要构建的提交>:refs/heads/qianmo/build/<名字>`，构建的就是这个分支的头提交。

注意：GitHub 文档写明 `workflow_dispatch`「只在 workflow 文件位于默认分支时接收事件」。fork 的默认分支目前是 `main`（纯镜像，没有这个文件），所以要先把默认分支设为 `qianmo/main` 才能触发（待负责人定，见第 9 节）。`--ref` 决定用哪个分支上的 workflow 文件和源码；要构建别的分支、标签或提交，加 `-f ref=…`。artifact 下载后是 zip，解压出的二进制没有执行位，先用 `sha256sum -c <名字>.sha256` 核对，再 `chmod +x`。

**备选**：在任意 Linux 主机（x86_64 或 aarch64）上直接执行脚本；aarch64 产物在 aarch64 机器上编。机器内存不足（例如 1–2 GB 的节点）时编不动，不要在这类机器上编：

```sh
qianmo/build-linux.sh [输出目录]   # 输出目录缺省为 codex-rs/target/qianmo-dist
```

脚本按 `codex-rs/rust-toolchain.toml` 钉的工具链（缺失时用 rustup 装 minimal profile）执行 `cargo build --release --locked --bin qmcode`，然后核对：构建前后 `Cargo.lock` 不变、`sha256sum -c` 通过、ELF 架构与本机一致（有 `readelf` 时）、`--version` 末行恰为 `qmcode <工作区版本>`、在临时 `HOME` 下只生成 `.qmcode`。有已跟踪文件未提交时拒绝构建，除非设 `QMCODE_ALLOW_DIRTY=1`。

## 7. 产物命名

`qmcode-<上游标签>-<短提交>-<架构>`，例如 `qmcode-rust-v0.158.0-0123456789-x86_64`。

- 上游标签：`rust-v` 加 `codex-rs/Cargo.toml` 的 `[workspace.package] version`（上游发行提交里两者一致）。不依赖 git 标签，因为 fork 上不放上游标签；本地有这个标签时，脚本会核对 HEAD 包含它。工作区版本是 `0.0.0`（上游 `main`，不是发行标签）时拒绝构建。
- 短提交：`git rev-parse --short=10 HEAD`，固定 10 位，不随仓库对象数变化。
- 架构：`x86_64` 或 `aarch64`。
- 工作区有未提交改动且设了 `QMCODE_ALLOW_DIRTY=1` 时，加后缀 `-dirty`。
- 同目录附带 `<名字>.sha256`（`sha256sum` 格式）、`<名字>.buildinfo`（标签、完整提交、工具链、主机、起止时间、编译秒数、sha256、字节数）、`<名字>.build.log`（cargo 完整输出）。

## 8. 合并记录

| 日期 | 上游标签 | 冲突文件 | 耗时 | 备注 |
|---|---|---|---|---|
| 2026-10-03 | `rust-v0.158.0` | —（基线） | — | P17.1 起点 |

## 9. 待办

| 事项 | 归属 | 状态 |
|---|---|---|
| 关闭 qmcode 的启动升级检查与升级提示，避免引导用户装回官方包（`check_for_update_on_startup` 等） | P17.3（与 `config/defaults.toml` 内置项一起改） | 未做 |
| fork 默认分支改为 `qianmo/main`，使 `qianmo-build-linux` 也可手动触发（push `qianmo/build/**` 已可触发，非必需） | 负责人 | 待定 |
| 是否在 fork 的 Actions 设置里停用会被自动触发的上游 workflow（第 4 节） | 负责人 | 待定 |
