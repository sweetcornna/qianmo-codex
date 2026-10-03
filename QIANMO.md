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
| `cli/src/main.rs` | clap 的 `name`、`bin_name`、`override_usage` 和 `completion` 子命令生成补全脚本时用的命令名改为 `qmcode`；`plugin marketplace` 帮助用例期望的用法行改为 `qmcode`；新增 `--version` 输出用例；`update` 子命令从帮助里隐藏，执行时直接报错（`run_update_command`），新增用例；报错、提示和退出信息里的 `codex <子命令>` 改为 `qmcode <子命令>`；新增帮助页巡检用例 `help_pages_use_qmcode_command_and_home`（遍历全部子命令含隐藏的，`--help` 里不得出现 `codex` 命令或 `~/.codex`） | `--version` 输出 `qmcode <版本>`，能与官方 `codex-cli` 区分；帮助文本与实际命令一致；`qmcode completion` 不能生成注册到 `codex` 上的补全，否则会覆盖官方补全；clap 把父命令名传给子命令，子命令上写死的 `bin_name = "codex plugin …"` 在帮助里不生效；上游的 `update` 按安装方式跑 npm、Homebrew 或 `chatgpt.com/codex/install.sh`，装的都是官方包 |
| `cli/src/snapshots/qmcode__*.snap`（4 个）、`cli/src/doctor/snapshots/qmcode__*.snap`（7 个） | 由 `codex__*.snap` 改名；`qmcode__exec_server_args_tests__exec_server_help_documents_remote_options.snap` 里的 `Usage: codex exec-server` 改为 `Usage: qmcode exec-server`。P17.3 又重录其中 5 个（`exec_server_help_documents_remote_options`、`unsupported_worktree_commands`、`terminal_check_prioritizes_unreadable_terminfo_over_warnings`、`doctor_human_report_environment_rows`、`copyable_items_color`），差异只有命令名、`~/.qmcode` 和 insta 去掉的 `assertion_line` 元数据行 | insta 快照文件名的前缀是 crate 名，二进制改名后 crate 名随之变为 `qmcode`；用法行跟随 `bin_name`；P17.3 跟随下面「界面命令名」一行 |
| `utils/home-dir/src/lib.rs` | `find_codex_home()` 读 `QMCODE_HOME`，默认 `~/.qmcode`；错误信息同步；新增用例确认设了 `CODEX_HOME` 也不影响结果 | 状态目录隔离的唯一入口：会话、sqlite、日志、arg0 临时目录、daemon socket、`.env`、登录凭据都由它派生 |
| `config/src/loader/mod.rs` | Unix 系统级 `config.toml`、`requirements.toml` 改到 `/etc/qmcode/`；挂上 `qianmo_defaults_tests` 用例模块 | 同机装了官方企业配置时，qmcode 不读它 |
| `config/defaults.toml` | 加三项：`check_for_update_on_startup = false`；`notify = ["qm", "handoff", "sync", "--hook", "qmcode"]`；`[mcp_servers.qianmo]`（`command = "qm"`、`args = ["handoff", "mcp"]`） | 接力入口，见第 10 节；上游的启动升级检查与升级提示会引导用户装回官方包 |
| `config/src/loader/qianmo_defaults_tests.rs`（新增） | 内置层含上面三项；用户层只写 `[mcp_servers.qianmo] enabled = false` 时按键合并，用户层的 `notify` 整体替换内置值 | 钉住第 10 节写的合并语义 |
| `config/src/loader/layer_io.rs` | 旧版托管配置 `managed_config.toml` 改到 `/etc/qmcode/` | 同上 |
| `app-server-daemon/src/settings.rs` | `auto_update_enabled` 的结构体默认值和反序列化默认值都改为 `false` | 托管 daemon 开着自动更新时会从上游地址装回官方包并切过去运行 |
| `app-server-daemon/src/settings_tests.rs` | 遥测标签用例按默认关闭更新期望值；新增「没有设置文件时自动更新为关」用例 | 跟随默认值 |
| `app-server-daemon/src/update_loop_tests.rs` | 两条测更新器行为的用例在开头显式写入 `autoUpdateEnabled: true` | 这两条原先靠默认开启；改后仍覆盖「开启时」的更新器路径 |
| `tui/src/external_editor.rs` | 外部编辑器草稿目录的默认家目录回退由 `~/.codex` 改为 `~/.qmcode` | 这是写入路径：沙箱策略下状态目录不可用时会回退到这里建 `editor/` 临时文件，不改会写进官方目录 |
| `tui/src/external_editor_tests.rs` | 「默认家目录可写时退到工作区」用例把 `~/.qmcode` 设为可写（原为 `~/.codex`） | 跟随上面的回退目录；不改的话，HOME 不在 `/tmp` 下时用例失败，还会在真实 `~/.qmcode/editor` 建目录 |
| `tui/src/app/tests.rs` | 「编辑器目录可写时拒绝」快照用例的回退目录改为 `~/.qmcode` | 同上 |
| `tui/src/status/helpers.rs` | 状态页 AGENTS.md 摘要用例的全局路径与内联快照改为 `~/.qmcode/AGENTS.md` | 显示路径跟随状态目录 |
| `tui/src/history_cell/snapshots/codex_tui__history_cell__tests__mcp_tools_output_{lists_tools_for_hyphenated_server_names,masks_sensitive_values}.snap` | `/mcp` 输出多出内置的 `qianmo` 一项（`Command: qm handoff mcp`） | 两条用例从带内置层的测试配置出发，内置项照常列出 |
| `tui/src/app/tests/safety_buffering.rs` | 「安全重试」用例的测试配置关掉内置 MCP（完整表加 `enabled = false`）与 `notify`（`notify = []`） | 这条用例起内嵌 app-server 跑真实回合，会按内置配置拉起 `qm handoff mcp`；`PATH` 上没有 `qm` 时，它快照的历史里多出两条 MCP 启动失败提示，结果随环境变 |
| `tui/src/slash_command.rs` | 加 `Handoff`、`Pull` 两个变体（弹窗里排在 `/app` 之后）与说明；回合进行中不可用 | 接力入口，见第 10.3 节 |
| `tui/src/chatwidget/slash_dispatch.rs` | `/handoff`、`/pull` 经 `submit_shell_command_with_history` 分别执行 `qm handoff now`、`qm handoff pull`；远程会话（`--remote` 接的不是本机 daemon）拒绝执行；排队分发后等命令结束再放行下一条输入 | 复用界面现成的 `!` 执行路径，不另起进程 |
| `tui/src/chatwidget/input_submission.rs` | `submit_shell_command_with_history` 改为 `pub(super)` | 供上一行调用 |
| `tui/src/chatwidget/tests.rs`、`tui/src/chatwidget/tests/qianmo_handoff_tests.rs`（新增） | 命令表含两项；分发到 `qm handoff now` / `qm handoff pull`；输入框敲 `/handoff` 后命令输出显示在会话里；回合进行中拒绝；远程会话拒绝、本机 daemon 照常 | 见第 10.3 节 |
| `tui/src/bottom_pane/snapshots/codex_tui__bottom_pane__command_popup__tests__command_popup_default_items.snap` | 命令列表多出 `/handoff`、`/pull` 两行 | 跟随枚举 |
| `tui/src/history_cell/session.rs`、`tui/src/status/card.rs` | 会话头卡片、紧凑会话头、纯文本会话头和 `/status` 卡片的标题 `OpenAI Codex` 改为 `qmcode` | 计划 D-5 定产品名不用 Codex 商标；本文件没有另定界面产品名，用二进制名 |
| `exec/src/event_processor_with_human_output.rs` | `qmcode exec` 人读输出开头的 `OpenAI Codex v<版本>` 改为 `qmcode v<版本>` | 同上 |
| `tui/src/app/tests/startup_frame_tests.rs`、`tui/src/app/tests/session_lifecycle_requests.rs`、`tui/src/chatwidget/rendering_tests.rs`、`tui/tests/suite/focus_palette.rs` | 判断会话头是否出现的断言改为找 `>_ qmcode`；`rendering_tests.rs` 的内联快照重录 | 跟随标题。`tui/tests` 是集成测试，不在合并门禁内，未跑 |
| `tui/src/**/snapshots/*.snap`（47 个） | 标题改为 `qmcode`；其中 31 个原来录的是 `v0.0.0`，重录后是 `v0.158.0` | 跟随标题，见第 5 节失败数说明 |
| 界面命令名（P17.3）：`cli/src/{login,mcp_cmd,plugin_cmd,marketplace_cmd,doctor,daemon_install,exec_server_command,migrate_rollouts,queue_cmd,state_db_recovery}.rs`、`cli/src/doctor/{background,desktop,network,output}.rs`、`cli/src/doctor/desktop/macos_security.rs`、`exec/src/{cli,lib}.rs`、`utils/cli/src/{config_override,resume_command}.rs`、`cloud-tasks/src/{cli,lib}.rs`、`app-server/src/log_write_warning.rs`、`app-server/src/request_processors/{thread_processor,thread_queue_processor}.rs`、`app-server/src/request_processors/account_processor/bedrock_setup.rs`、`app-server-transport/src/transport/websocket.rs`、`app-server-daemon/src/{lib,migration,prepare_install}.rs`、`chatgpt/src/{chatgpt_client,connectors}.rs`、`codex-mcp/src/connection_manager/startup.rs`、`responses-api-proxy/src/read_api_key.rs`、`sandboxing/src/seatbelt.rs`、`tui/src/{lib,keymap,tooltips,session_queue_commands,startup_orchestration}.rs`、`tui/src/app/{agents_overview,exit_summary,managed_worktree_creation,thread_goal_actions}.rs`、`tui/src/status/card.rs`、`tui/assets/tooltips.txt` | 用户看得到的报错、提示、`--help` 文本（clap 的 `override_usage`、`after_help` 和渲染成帮助的 doc 注释）、启动提示、退出提示（`Reconnect: …`、`To continue this session, run: …`、`Stop the current turn: run …`）和 `app-server --listen ws://` 横幅里的 `codex <子命令>` 改为 `qmcode <子命令>`，`~/.codex/config.toml` 改为 `~/.qmcode/config.toml`。只改字符串，不改逻辑；保留的见第 3 节「界面文字里保留的 `codex`」 | P17.1 遗留：用户照提示敲 `codex …` 会跑官方二进制、改官方状态目录 |
| `tui/src/session_start.rs`、`tui/src/session_start_tests.rs` | 「会话已归档」引导的识别同时认 `` Run `qmcode unarchive `` 和 `` Run `codex unarchive ``；用例两种都测 | 本 fork 的 app-server 报错文本改了；`--remote` 接上游 app-server 时对方仍说 `codex unarchive` |
| 上面两行对应的单测期望：`cli/src/main.rs`、`cli/src/daemon_install_tests.rs`、`cli/src/doctor/output.rs`、`app-server/src/log_write_warning_tests.rs`、`codex-mcp/src/connection_manager_tests.rs`、`tui/src/keymap/conflict_tests.rs`、`tui/src/app/tests/{background_exit_tests,session_summary,worktree_background_terminals_tests}.rs`、`tui/src/tooltips.rs` 的内联快照，以及 5 个 TUI 快照：`tui/src/snapshots/codex_tui__app__agents_overview__tests__agents_overview_embedded.snap`、`tui/src/app/snapshots/codex_tui__app__thread_goal_actions__tests__thread_goal_ephemeral_error_message_renders_snapshot.snap`、`tui/src/app/tests/snapshots/codex_tui__app__tests__background_exit_tests__{remote,interrupted,daemon}_disconnect_exit.snap` | 期望值跟随；快照差异只有命令名和 insta 去掉的 `assertion_line` 行 | — |
| 集成测试期望：`cli/tests/{cloud_auth,mcp_list,features}.rs`、`cli/tests/snapshots/doctor_path_safety__doctor_config_{not_found,invalid_data,error_location}.snap`、`app-server/tests/suite/v2/{bedrock_setup,thread_resume,feedback}.rs`、`tui/tests/suite/snapshots/all__suite__focus_palette__daemon_auto_start_failure.snap` | 期望值跟随 | 不在合并门禁内（第 4 节），未跑。`core/tests/suite/rmcp_client.rs` 里 ``Run `codex mcp login …` `` 的期望未改（`core` 不碰），这条用例适配时要一起改 |
| `Cargo.lock` | 158 个工作区 crate 的 `version` 由 `0.0.0` 改为 `0.158.0`，其余不变 | 上游发行提交只改 `Cargo.toml` 的版本号，不提交这一步就无法 `--locked` 构建。这是 cargo 生成的文件，不加文件头：cargo 下次非 `--locked` 改写时会把注释行去掉 |
| `../QIANMO.md`（新增） | 本文件 | 改动清单、合并步骤、构建方法 |
| `../qianmo/build-linux.sh`（新增） | Linux 原生构建脚本：编 `qmcode` 与 `codex-code-mode-host` 两个 bin，都剥离、都出 `.debug`，放进同一个产物目录 | 见第 6、7 节 |
| `../qianmo/fetch-rusty-v8.sh`（新增） | 下载并校验 `codex-code-mode-host` 链接的 V8 预编译库，打印 `RUSTY_V8_ARCHIVE`、`RUSTY_V8_SRC_BINDING_PATH` | 见第 6 节 |
| `../.github/workflows/qianmo-build-linux.yml`（新增） | push `qianmo/build/**` 或手动触发的 Linux x86_64 构建 workflow | 见第 6 节 |

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

- 界面文字里保留的 `codex`（P17.3 逐条判定；`OpenAI Codex` 标题和 `codex <子命令>` 提示已改，见第 2 节）：

| 位置 | 文字 | 为什么不改 |
|---|---|---|
| `tui/src/app/event_dispatch.rs` | `/agents` 起后台服务后的提示 ``Run `codex agents` in another terminal; …`` | 第 5 节约定该文件不碰。界面上与 `/agents` 列表里已改的 ``Open `qmcode agents` …`` 不一致 |
| `tui/src/onboarding/welcome.rs`、`login/src/device_code_auth.rs` | `Welcome to Codex`、`OpenAI's command-line coding agent` | 产品名叙述，不是命令；本文件没有另定界面产品名，改它要另定文案 |
| 各处说明文字里的 `Codex`、`Codex CLI`、`the local Codex service`；`tui/src/chatwidget/tool_requests.rs` 的 `codex could …`、`codex to …`；`app-server` 账号处理里的 `codex account authentication required …` | 产品名或账号体系的叙述 | 同上；照着敲不会跑到官方二进制 |
| `tui/src/app/background_requests.rs` | `"codex plugins are disabled"` | 匹配服务端报错文本，不是显示 |
| `cli/src/plugin_cmd.rs`、`cli/src/marketplace_cmd.rs` | `bin_name = "codex plugin …"` | clap 用父命令传下来的名字，帮助里不生效；`help_pages_use_qmcode_command_and_home` 用例钉住 |
| `tui/src/update_action.rs` | 升级动作里的 `codex`、`brew upgrade --cask codex` 等 | 升级提示默认关闭（第 4 节「升级入口」）；它们是要执行的官方安装命令，改名反而装不上 |
| `cli/src/doctor/sandbox.rs`、`cli/src/sandbox_setup.rs`、`app-server-daemon/src/backend/windows.rs` | `codex sandbox setup …`、`codex.exe` | 只在 Windows 编进去；M1 不出 Windows 产物 |
| `app-server-daemon/src/lib.rs` 的 `ensure_supported_platform` | `codex app-server daemon lifecycle is only supported …` | 只在非 Unix、非 Windows 平台编进去 |
| `exec-server/src/environment_toml.rs` | `codex exec-server --listen stdio` | 用例数据 |
| rustdoc 注释（不渲染成 `--help` 的）、`tui/src/cli.rs` 隐藏参数的注释、开发工具（`app-server-test-client`、`cli/e2e_benches`、`cli/src/bin/logs_client.rs`）、`default.nix`、`BUILD.bazel` | — | 用户看不到，或不随 `qmcode` 发布 |
| `skills/src/assets/samples/**` 的说明与脚本 | `$CODEX_HOME`、`~/.codex` | 见第 4 节「内置技能的脚本」；不是显示问题 |

## 4. 已知未适配（合并、跑测试前必读）

- **上游集成测试**（按 `utils/cargo-bin` 的查找逻辑推断，未实跑）：`cli/tests`、`core/tests`、`app-server/tests`、`tui/tests`、`rmcp-client/tests` 里大量用 `cargo_bin("codex")` 找二进制，并给子进程设 `CODEX_HOME` 做隔离。fork 后 cargo 不再设 `CARGO_BIN_EXE_codex`，这些用例会在起进程前失败；但若 `target/debug/` 下还留着改名前编出的 `codex`，用例会跑到那个旧二进制。不要只把 `cargo_bin("codex")` 改成 `qmcode`：环境变量不跟着改的话，子进程会落到真实的 `~/.qmcode`。`test-binary-support` 在测试启动时只设 `CODEX_HOME`，`core`、`exec-server` 的测试因此会在 `HOME` 下建 `.qmcode/tmp/arg0`（按代码推断；`codex-tui` 单测实测会在 `HOME` 下建 `.qmcode/tmp/arg0`）。这些集成测试不在合并门禁内（第 5 节），跑的话按第 5 节把 `HOME` 指到临时目录。
- **Windows**：`%ProgramData%\OpenAI\Codex` 下的系统级配置、Windows 沙箱安装助手出错时按 `CODEX_HOME` 写日志、daemon 在 Windows 上转绝对路径的环境变量列表，都未改。M1 不出 Windows 产物。
- **macOS 托管偏好**：MDM 域 `com.openai.codex` 未改，qmcode 仍会读管理员强制下发的官方 Codex 配置。
- **Bazel**：`BUILD.bazel` 仍按 `codex` 命名。本 fork 只支持 cargo 构建。
- **升级入口**：上游的升级检查查的是 `openai/codex` 的发行，给出的升级命令装的是官方包（npm `@openai/codex`、Homebrew cask `codex`、`chatgpt.com/codex/install.sh`），装上的是 `codex`，不会更新 qmcode。处理：
  - 启动时的升级检查、升级弹窗和「Update available」提示默认关闭（`config/defaults.toml` 的 `check_for_update_on_startup = false`）。用户在 `config.toml` 里写 `check_for_update_on_startup = true` 会重新打开上游这一套，不要打开。
  - `qmcode update` 从帮助里隐藏；执行时不做任何安装，报错 ``qmcode update` is not available: qmcode does not update itself, and the upstream updater would install the official Codex package instead. Install a newer qmcode build to update.`` 并以非零退出码退出。debug 与 release 构建行为相同。
  - 未改：`qmcode doctor` 的 `updates` 一行仍会请求 GitHub `openai/codex` 的最新发行号并显示安装方式（只读，不安装）；`/daemon` 菜单的「Install latest public stable」与 `qmcode app-server daemon update` 仍从 `chatgpt.com/codex/install.sh` 装官方包到 `~/.qmcode/packages/`（第 3 节，手动触发，节点不用 daemon）。
- **上游 workflow**：fork 上 Actions 已启用，上游的 29 个 workflow 都处于启用状态。push `qianmo/*` 分支不会触发任何上游 workflow（分支过滤只有 `main` 和 `**full-ci**`，分支名不要带 `full-ci`）；但下列操作会触发：push fork 的 `main`（`blocking-ci`、`postmerge-ci`）、fork 内开任何 PR（`blocking-ci`、`v8-canary`）、推 `rust-v*.*.*` 标签（`rust-release`，跑完还会经 `workflow_run` 带起 `python-sdk-cli-release`；`rusty-v8-v*`、`codex-zsh-v*` 同理）。`cla`、`issue-*`、`close-stale-contributor-prs`、`python-sdk-release` 有 `openai/codex` 仓库判断，在 fork 上触发后跳过。runner 写成 `${{ github.event.repository.name }}-*` 的 job 在 fork 上解析为 `qianmo-codex-*` 自定义 runner，和 `macos-15-xlarge` 的 job 一样开跑即失败，不会排队（2026-09-29 push `main` 的两次运行实测如此）。**不要把上游标签推到 fork**；构建脚本也不依赖标签。是否在 fork 的 Actions 设置里停用这些 workflow，待负责人定（第 9 节）。
- **Linux 沙箱依赖系统 `bwrap`**：产物不带 bubblewrap。qmcode 先找 `PATH` 上支持 `--perms` 的 `bwrap`，再找可执行文件旁的 `codex-resources/bwrap` 或 `bwrap`（`linux-sandbox/src/launcher.rs`）。都没有时，`read-only`、`workspace-write` 下的命令全部失败（`bubblewrap is unavailable`），`features.use_legacy_landlock` 也不能绕过（`filesystem-restricted execution requires bubblewrap`）；只有 `danger-full-access` 能跑命令。2026-10-03 在未装 bubblewrap 的 Debian 13 节点上实测如此。上游 release 另编 `--bin bwrap`（需要 `libcap-dev`）并把摘要编进二进制，本 fork 没做。
- **内置技能的脚本**（读代码，未实跑）：`skills/src/assets/samples/skill-installer/scripts/{install-skill-from-github,list-skills}.py` 取 `CODEX_HOME`，没设时用 `~/.codex`；`imagegen/references/cli.md` 教模型 `export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"`。qmcode 不给工具子进程设 `CODEX_HOME`（`core/src` 里没有注入它的代码），所以模型按 `skill-installer` 装技能时会装进官方的 `~/.codex/skills`，qmcode 读不到。这是隔离缺口，不是显示问题，P17.3 没改；改法是给工具子进程注入 `CODEX_HOME=<qmcode 状态目录>`（要动 `core`），或改这几份脚本与说明。
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
3. 复查上游新代码：重新搜 `"CODEX_HOME"`、`join(".codex")`、`/etc/codex`、`bin_name = "codex`，按第 3 节口径逐条判定。cli 二进制若新增了 `codex__*.snap` 快照，改名为 `qmcode__*.snap`。界面文字再搜一遍 ``rg -n '"codex |`codex[ `]|codex exec|codex --remote|[Rr]un codex |OpenAI Codex|~/\.codex' --glob '*.rs' --glob '*.txt'``，新出现的命令名、路径照第 2 节「界面命令名」一行改，按第 3 节「界面文字里保留的 `codex`」判定留不留；`--help` 文本由 `help_pages_use_qmcode_command_and_home` 用例兜底。
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
   `PATH` 上不能有 `qm`（`command -v qm` 无输出）：`codex-tui` 里起内嵌 app-server 跑真实回合的用例会按内置配置（第 10 节）拉起 `qm handoff mcp`，回合结束调 `qm handoff sync`。有 `qm` 时先把它所在目录移出 `PATH` 再跑。

   跑完 `target/qianmo-test-home` 下应只有 `.qmcode`。在 `rust-v0.158.0` 上（P17.1 基线），`codex-tui` 有 40 条用例失败：
   - 39 条是快照差异：快照是在上游 `main`（工作区版本 `0.0.0`）上录的，发行标签把版本改成了 `0.158.0`，差异只有版本号和它引起的排版宽度；
   - 1 条是 insta 报「Insta does not allow inline snapshot assertions in loops」，落在 `tui/src/app/tests/safety_buffering.rs` 里共用 `interrupt_after_inactive_steer` 的两条用例之一，哪条失败每次不同。

   P17.3 把界面标题改成 `qmcode`（第 2 节），带标题的快照全部重录，重录时版本号随之变成 `0.158.0`，所以那些用例不再失败。现在剩 10 条：
   - 9 条只差版本号：`app::daemon_menu::tests::daemon_menu_is_read_only_and_confirmation_can_cancel_or_handoff`、`app::tests::active_reconnect::reconnect_allows_slow_hydration_but_bounds_a_stalled_server`、`app::tests::navigation_reconnect::reconnect_daemon_command_center_after_socket_replacement_without_a_conversation`、`history_cell::tests::{pnpm,standalone_unix,standalone_windows,vite_plus}_update_available_history_cell_snapshot`、`update_prompt::tests::{update_prompt_snapshot,long_update_command_keeps_selected_skip_visible_in_a_short_viewport}`；
   - 1 条是上面那条 insta 报错。

   判据是失败数不增加，快照差异仍只含版本号。机器负载高时（2026-10-03 实测负载 11 左右），`app::tests::session_lifecycle_requests` 下几条带秒级超时的用例偶尔报 `deadline has elapsed` 或 `timed out waiting for MCP task registration`，单独重跑能过；判定前单独重跑一次。下次合并上游发行标签时，重录过的快照文件可能与上游改动冲突：取上游一侧后重跑本门禁，用 `cargo insta accept --snapshot <文件>` 只接受差异是标题或版本号的那些。失败的快照用例会在源码树里留下未跟踪的 `*.snap.new` 和 `.*.pending-snap`，核对完删掉，不要提交。
6. 复查上游 workflow：合并可能带进新的 workflow 文件，或改动已有文件的触发条件。按第 4 节「上游 workflow」一条重新核对，不要推上游标签。
7. 重跑 P17.2 第 3、5 项探针；重新出 Linux 产物（第 6 节）。
8. 在第 8 节记一行：日期、标签、冲突文件、耗时。

## 6. 构建

产物是两个程序，必须放在同一目录、辅助程序不改名：

- `qmcode`：入口。
- `codex-code-mode-host`：code mode 的执行进程。内置模型目录里 `tool_mode` 为 `code_mode_only` 的模型（`gpt-6-luna`、gpt-6 / gpt-5.6 系列）的每次工具调用都经它执行；找不到它时工具调用直接失败，不回退普通工具。qmcode 查找它的顺序（`install-context/src/lib.rs` 的 `code_mode_host_program`）：包布局 `<包>/codex-resources/`（`<包>/bin/` 下的可执行文件且有 `<包>/codex-package.json`），或 `$QMCODE_HOME/packages/standalone/releases/<版本>/codex-resources/`；否则 qmcode 可执行文件所在目录（取 `current_exe()` 的父目录，Linux 上已解析软链接，所以经软链接调用时找的是真实文件旁边）。没有环境变量或配置项能另指路径。

`codex-code-mode-host` 链接 V8（`v8 = =150.4.0`，开 `v8_enable_sandbox`）。v8 的构建脚本默认去 denoland/rusty_v8 下 `ptrcomp_sandbox` 变体的预编译库，那边不发布这个变体，cargo 直接失败。`qianmo/fetch-rusty-v8.sh <目标三元组> [目录]` 照上游 `.github/actions/setup-rusty-v8` 的做法，从上游 `openai/codex` 的 `rusty-v8-v<版本>` 发行下载预编译库与绑定，用仓库内 `third_party/v8/rusty_v8_<版本>_release_manifests.sha256` 校验清单、再逐文件校验，最后打印两个环境变量。目录缺省为 `codex-rs/target/qianmo-rusty-v8`，已有文件校验通过就不重下。需要 `curl` 和 python3 ≥ 3.11。qmcode 本身不链接 V8。

本机（macOS，自测用，不作为发布产物；macOS 上不交叉编译 Linux）：

```sh
export $(qianmo/fetch-rusty-v8.sh aarch64-apple-darwin)
cd codex-rs
cargo build --release --locked --bin qmcode --bin codex-code-mode-host
# 产物：codex-rs/target/release/qmcode、codex-rs/target/release/codex-code-mode-host
```

Linux 发布产物**以 GitHub Actions 为主**：workflow `.github/workflows/qianmo-build-linux.yml` 有两种触发：push 任何 `qianmo/build/**` 分支（不需要改默认分支，日常用这个），或手动 `workflow_dispatch`（可选输入 `ref`，要求文件在默认分支上）。它在 `ubuntu-24.04`（x86_64）上执行：

1. checkout（不保留凭据）；
2. 用 apt 装 `build-essential pkg-config libssl-dev`；
3. 用 rustup 装 `rust-toolchain.toml` 钉的工具链；
4. 执行 `qianmo/build-linux.sh`；
5. 用 `actions/upload-artifact` 把产物目录里的 7 个文件（两个已剥离的程序、两个 `.debug`、`.sha256`、`.buildinfo`、`.build.log`，见第 7 节）作为一个 artifact 上传，保留 30 天；构建失败时单独上传日志。

第三方 action 都钉完整的提交 sha。触发方式：

```sh
gh workflow run qianmo-build-linux.yml --repo sweetcornna/qianmo-codex --ref <分支> [-f ref=<分支/标签/提交>]
```

日常触发：`git push origin <要构建的提交>:refs/heads/qianmo/build/<名字>`，构建的就是这个分支的头提交。

注意：GitHub 文档写明 `workflow_dispatch`「只在 workflow 文件位于默认分支时接收事件」。fork 的默认分支目前是 `main`（纯镜像，没有这个文件），所以要先把默认分支设为 `qianmo/main` 才能触发（待负责人定，见第 9 节）。`--ref` 决定用哪个分支上的 workflow 文件和源码；要构建别的分支、标签或提交，加 `-f ref=…`。artifact 下载后是 zip，解压出的二进制没有执行位，先用 `sha256sum -c <名字>.sha256` 核对，再对 `<名字>` 和 `codex-code-mode-host` 都 `chmod +x`。部署时两个程序放同一目录，`codex-code-mode-host` 不改名；一个版本一个目录，不要让不同版本的 qmcode 共用一个 `codex-code-mode-host`。

**备选**：在任意 Linux 主机（x86_64 或 aarch64）上直接执行脚本；aarch64 产物在 aarch64 机器上编。机器内存不足（例如 1–2 GB 的节点）时编不动，不要在这类机器上编：

```sh
qianmo/build-linux.sh [输出目录]   # 输出目录缺省为 codex-rs/target/qianmo-dist
```

脚本按 `codex-rs/rust-toolchain.toml` 钉的工具链（缺失时用 rustup 装 minimal profile），先用 `qianmo/fetch-rusty-v8.sh` 取本机目标的 V8 预编译库，再执行 `cargo build --release --locked --bin qmcode --bin codex-code-mode-host`，然后核对：构建前后 `Cargo.lock` 不变、`sha256sum -c` 通过、两个程序的 ELF 架构都与本机一致（有 `readelf` 时）、`codex-code-mode-host --help` 能运行、`--version` 末行恰为 `qmcode <工作区版本>`、在临时 `HOME` 下只生成 `.qmcode`。有已跟踪文件未提交时拒绝构建，除非设 `QMCODE_ALLOW_DIRTY=1`。

## 7. 产物命名

`qmcode-<上游标签>-<短提交>-<架构>`，例如 `qmcode-rust-v0.158.0-0123456789-x86_64`，下称「名字」。它同时是产物目录名（脚本写到 `<输出目录>/<名字>/`，每次构建先清空这个目录；Actions artifact 也叫这个名字）和 qmcode 程序的文件名。

- 上游标签：`rust-v` 加 `codex-rs/Cargo.toml` 的 `[workspace.package] version`（上游发行提交里两者一致）。不依赖 git 标签，因为 fork 上不放上游标签；本地有这个标签时，脚本会核对 HEAD 包含它。工作区版本是 `0.0.0`（上游 `main`，不是发行标签）时拒绝构建。
- 短提交：`git rev-parse --short=10 HEAD`，固定 10 位，不随仓库对象数变化。
- 架构：`x86_64` 或 `aarch64`。
- 工作区有未提交改动且设了 `QMCODE_ALLOW_DIRTY=1` 时，加后缀 `-dirty`。
- 产物目录里的 7 个文件：

  | 文件 | 内容 |
  |---|---|
  | `<名字>` | qmcode，已剥离 |
  | `<名字>.debug` | qmcode 的调试符号，经 `.gnu_debuglink` 关联 |
  | `codex-code-mode-host` | 辅助程序，已剥离；**不改名**，qmcode 按这个名字在自己所在目录找它 |
  | `codex-code-mode-host.debug` | 辅助程序的调试符号 |
  | `<名字>.sha256` | `sha256sum` 格式，上面 4 个文件各一行 |
  | `<名字>.buildinfo` | 标签、完整提交、工具链、主机、起止时间、编译秒数，两个程序的 sha256 与字节数，V8 预编译库文件名 |
  | `<名字>.build.log` | cargo 完整输出 |

- 剥离的做法：上游 release 配置 `strip = false`、留给打包剥离，这里照同样的拆法做。首次未剥离的 qmcode 1.38 GB，部署不用它。

## 8. 合并记录

| 日期 | 上游标签 | 冲突文件 | 耗时 | 备注 |
|---|---|---|---|---|
| 2026-10-03 | `rust-v0.158.0` | —（基线） | — | P17.1 起点 |

## 9. 待办

| 事项 | 归属 | 状态 |
|---|---|---|
| 关闭 qmcode 的启动升级检查与升级提示，避免引导用户装回官方包（`check_for_update_on_startup` 等） | P17.3（与 `config/defaults.toml` 内置项一起改） | 已完成：启动检查默认关，`qmcode update` 拒绝执行（第 4 节「升级入口」） |
| fork 默认分支改为 `qianmo/main`，使 `qianmo-build-linux` 也可手动触发（push `qianmo/build/**` 已可触发，非必需） | 负责人 | 待定 |
| 是否在 fork 的 Actions 设置里停用会被自动触发的上游 workflow（第 4 节） | 负责人 | 待定 |
| Linux 产物是否加编 `bwrap`（第 4 节「Linux 沙箱依赖系统 `bwrap`」）。节点要用 `read-only`、`workspace-write` 沙箱时需要；P17.5 节点桥按计划用 `danger-full-access`，不需要 | 负责人 | 待定 |

## 10. 接力入口（P17.3）

### 10.1 内置配置

`config/defaults.toml` 编译进二进制，是优先级最低的配置层（`include_str!`，见 `config/src/loader/mod.rs`）；上面各层与它合并时，表按键递归合并，数组和标量整体替换。阡陌加的三项：

| 键 | 值 | 作用 |
|---|---|---|
| `[mcp_servers.qianmo]` | `command = "qm"`、`args = ["handoff", "mcp"]` | 给模型的接力工具（`qianmo_*`），由阡陌侧 `qm handoff mcp` 提供 |
| `notify` | `["qm", "handoff", "sync", "--hook", "qmcode"]` | 每个回合结束后同步会话 |
| `check_for_update_on_startup` | `false` | 见第 4 节「升级入口」 |

- **关掉内置 MCP**：在 `~/.qmcode/config.toml` 写完整表：

  ```toml
  [mcp_servers.qianmo]
  command = "qm"
  args = ["handoff", "mcp"]
  enabled = false
  ```

  只写 `enabled = false` 时有效配置也会关掉它（按键合并），但 `qmcode mcp add`、`qmcode mcp remove` 单独解析用户文件，半张表在那里不合法，两个命令都会报 `invalid transport in 'qianmo'`（P17.2 第 6 项 T4）。`qmcode mcp remove qianmo` 删不掉内置项（读代码，未实跑）。也可以按次关：`-c mcp_servers.qianmo.enabled=false`。
- **用户自设 `notify` 会整个顶掉内置值**，接力同步随之停止。两者都要时，用户自己写一个包装脚本当 `notify`，在里面先调自己的程序，再调 `qm handoff sync --hook qmcode "<最后一个参数>"`。`notify = []` 等于关闭。项目级 `.codex/config.toml` 不能设 `notify`（上游的项目层禁止项），不影响内置层。
- `qm` 按 qmcode 进程的 `PATH` 查找。找不到时 MCP 报启动失败、线程照常（P17.2 第 6 项 T6），界面在每个新线程开头显示两条提示：``MCP client for `qianmo` failed to start: MCP startup failed: No such file or directory (os error 2)`` 和 `MCP startup incomplete (failed: qianmo)`；notify 的进程起不来，只记日志。没装 `qm` 又不想看到提示时，按上面的写法关掉。
- **节点上不要带这两项**：节点上有 `qm`（节点桥 `qm handoff node`），不关的话节点线程会拉起 `qm handoff mcp`，每个回合结束还会调 `qm handoff sync`。P17.5 起节点 app-server 时加 `-c mcp_servers.qianmo.enabled=false -c 'notify=[]'`，或写进节点 `QMCODE_HOME` 下的 `config.toml`。

### 10.2 给阡陌侧的接口约定

**`qm handoff mcp`**（P17.3 阡陌侧）

- stdio MCP。qmcode 每个线程启动时各拉起一份（argv 为 `qm handoff mcp`）；`/mcp`、app-server 的 `mcpServerStatus/list` 会再起一份（P17.2 第 6 项 T2）。必须无状态、可多实例并发。
- 进程的工作目录是线程的 `cwd`（实测，见第 10.3 节实测记录；代码在 `core/src/session/mcp.rs` 的 `local_process_cwd`）。
- **环境是过滤过的**，不是 qmcode 进程的完整环境：只带 `HOME`、`LOGNAME`、`PATH`、`SHELL`、`USER`、`LANG`、`LC_ALL`、`TERM`、`TMPDIR`、`TZ`（macOS 另有 `__CF_USER_TEXT_ENCODING`）中已设置的那些、自定义 CA 相关变量，以及配置里 `env`、`env_vars` 指定的变量（`rmcp-client/src/utils.rs` 的 `DEFAULT_ENV_VARS`、`create_env_for_mcp_server`）。实测拿不到 `QMCODE_HOME`；也没有 `CODEX_THREAD_ID`、`SSH_AUTH_SOCK` 和模型 key。所以：
  - 不能靠 `CODEX_THREAD_ID` 认会话，按计划用工作目录去 `sessions.json` 里找；
  - 用户改过 `QMCODE_HOME` 时，`qm handoff mcp` 看不到，只能用 `qm handoff sync`（拿得到完整环境）记下的会话文件绝对路径，或者在内置表里加 `env_vars = ["QMCODE_HOME"]` 把它透传过去（本次未加，待定）；
  - 推送中枢用专用钥匙（`-i <钥匙> -o IdentitiesOnly=yes`），不依赖 ssh-agent。

**`qm handoff sync --hook qmcode`**（P17.4）

- 完整 argv：`qm handoff sync --hook qmcode <JSON>`，JSON 总是最后一个参数（第 6 个，下标 5）。
- JSON 形状（`hooks/src/legacy_notify.rs` 的 `UserNotification`，字段名 kebab-case；上游用例 `legacy_notify_json_matches_historical_wire_shape` 钉住了它）：

  ```json
  {
    "type": "agent-turn-complete",
    "thread-id": "b5f6c1c2-1111-2222-3333-444455556666",
    "turn-id": "12345",
    "cwd": "/Users/example/project",
    "client": "codex-tui",
    "input-messages": ["Rename `foo` to `bar` and update the callsites."],
    "last-assistant-message": "Rename complete and verified `cargo build` succeeds."
  }
  ```

  - `type` 目前只有 `agent-turn-complete`。
  - `thread-id` 即会话 id，会话文件是 `$QMCODE_HOME/sessions/YYYY/MM/DD/rollout-*-<thread-id>.jsonl`；`turn-id` 与 rollout 里 `task_complete` 行的 `turn_id` 相同（P17.2 第 7 项）。
  - `client` 是接入 app-server 的客户端名，没有时整个键不出现；`last-assistant-message` 可能是 `null`。
  - `input-messages`、`last-assistant-message` 是对话原文，不要写日志。
- qmcode 即发即忘：标准输入接 `/dev/null`，标准输出与标准错误丢弃，不等进程退出，不看退出码。
- **进程的工作目录是 qmcode（或 app-server）进程自己的工作目录，不是线程的 `cwd`**（实测：app-server 在另一个目录启动时，notify 进程的工作目录跟 app-server 一致）。仓库位置一律取 JSON 里的 `cwd`。
- 环境是 qmcode 进程的完整环境（去掉 5 个启动上下文变量，P17.2 第 6 项），含 `PATH`、`QMCODE_HOME`（实测）、`SSH_AUTH_SOCK`，也含模型 key 所在的变量；没有 `CODEX_THREAD_ID`（实测），线程 id 在 JSON 里。不得记录环境变量。
- 只在模型回合结束后触发；`/handoff`、`!` 命令开的 shell 回合结束后不触发（实测）。
- 回合紧挨着时会连续触发；也会为没有 rollout 文件的临时线程触发（P17.2 第 5、7 项），找不到会话文件就跳过。

### 10.3 界面里的 `/handoff`、`/pull`

| 输入 | 执行 |
|---|---|
| `/handoff` | `qm handoff now` |
| `/pull` | `qm handoff pull` |

- 走界面现成的 `!` 执行路径（`ChatWidget::submit_shell_command_with_history`），经 app-server 的 `thread/shellCommand` 在 app-server 所在机器上执行，和输入 `!qm handoff now` 效果相同。命令输出（标准输出与标准错误合并）和退出码显示在会话里；它也会作为「用户 shell 命令」记录写进会话，下一回合发给模型（读代码：`core/src/tasks/user_shell.rs` 的 `persist_user_shell_output`）。
- 执行环境（2026-10-03 用 debug 构建的 `qmcode app-server` 加替身 `qm` 实测，见下）：`<用户登录 shell> -lc 'qm handoff now'`（本机是 `/bin/zsh -lc`）；工作目录是线程的 `cwd`；环境里有 `CODEX_THREAD_ID`（当前线程 id）、`CODEX_SESSION_ID`、`CODEX_VERSION`，以及 qmcode 进程的 `QMCODE_HOME`；标准输入不是终端；不进沙箱、不走审批（`thread/shellCommand` 的约定），默认超时 1 小时。
- 回合进行中不可用，界面提示 `'/handoff' is disabled while a task is in progress.`；排在队列里的 `/handoff` 在回合结束后执行，执行完再放行后面的输入。
- `--remote` 接到别的机器时（不是本机 daemon）拒绝执行，提示 ``'/handoff' is unavailable in remote sessions: it would run `qm handoff now` on the remote host.``：`!` 命令在 app-server 那台机器上跑，接到云端节点时会在节点上执行。本机 daemon 照常执行。
- 不带参数。读代码（`bottom_pane/chat_composer/slash_input.rs`）：`/handoff 目标…` 这类写法不会被识别成命令，会当作普通消息发给模型；未实测。

**给 `qm handoff now` 的约定（P17.3、P17.4）**

- 会话 id 取 `CODEX_THREAD_ID`；会话文件在 `$QMCODE_HOME/sessions/YYYY/MM/DD/rollout-*-<id>.jsonl`（`QMCODE_HOME` 没设时是 `~/.qmcode`）。
- **由 `/handoff` 调起时，`/handoff` 自己就是一个进行中的回合**：`thread/shellCommand` 先开一个独立回合再执行命令。实测 `qm handoff now` 运行时，会话文件末行是这个回合的 `{"type":"event_msg","payload":{"type":"task_started","turn_id":"<shell 回合 id>",…}}`，其后没有任何行、也没有对应的 `task_complete`；命令结束后才追加用户 shell 记录和 `task_complete`。P17.2 第 7 项第 5 条「最近一个 `task_started` 必须已有 `task_complete` 或 `turn_aborted`」的判据要排除这一行，否则从 `/handoff` 发起的转交永远判为「回合进行中」。可用的区分：环境里有 `CODEX_THREAD_ID`，且末尾这个 `task_started` 之后没有任何行；判完整时看它前面那个回合。
- 输出是给人看的文本，原样显示；失败时退出码非 0，界面把这条命令标成失败。

**实测记录**（2026-10-03，debug 构建，本机 macOS）：`qmcode app-server` 走 stdio，配置指向本机 127.0.0.1 上的假 Responses 服务（不调真实模型、不带 key），`PATH` 上放一个只记录调用的替身 `qm`。一个模型回合加一次 `thread/shellCommand "qm handoff now"`，替身记到 3 次调用：线程启动时 `qm handoff mcp`（工作目录是线程 cwd）；模型回合结束后 `qm handoff sync --hook qmcode <JSON>`；`qm handoff now`（工作目录是线程 cwd，`CODEX_THREAD_ID` 等于线程 id，输出显示在 `commandExecution` 条目的 `aggregatedOutput` 里，`source` 为 `userShell`）。shell 回合结束后没有触发 notify。另跑一次带 `-c 'notify=[]' -c mcp_servers.qianmo.enabled=false`：没有 MCP 启动、没有 notify，只剩 `qm handoff now`。
