// Copyright 2026 Qianmo AgentNest Team
// SPDX-License-Identifier: Apache-2.0

//! `/handoff` and `/pull` run `qm handoff now|pull` through the `!` shell-command path.

use super::*;
use crate::bottom_pane::slash_commands::BuiltinCommandFlags;
use crate::bottom_pane::slash_commands::find_builtin_command;
use crate::slash_command::built_in_slash_commands;
use crate::status::remote_connection::RemoteConnectionStatus;
use pretty_assertions::assert_eq;
use std::str::FromStr;

fn submit_composer_text(chat: &mut ChatWidget, text: &str) {
    chat.bottom_pane
        .set_composer_text(text.to_string(), Vec::new(), Vec::new());
    chat.handle_key_event(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
    chat.handle_key_event(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
}

fn next_shell_command(op_rx: &mut tokio::sync::mpsc::UnboundedReceiver<Op>) -> String {
    loop {
        match op_rx.try_recv() {
            Ok(Op::RunUserShellCommand { command }) => return command,
            Ok(_) => continue,
            other => panic!("expected RunUserShellCommand op, got {other:?}"),
        }
    }
}

fn history_entries(rx: &mut tokio::sync::mpsc::UnboundedReceiver<AppEvent>) -> Vec<String> {
    let mut entries = Vec::new();
    while let Ok(event) = rx.try_recv() {
        if let AppEvent::AppendMessageHistoryEntry { text, .. } = event {
            entries.push(text);
        }
    }
    entries
}

fn rendered_history(rx: &mut tokio::sync::mpsc::UnboundedReceiver<AppEvent>) -> String {
    drain_insert_history(rx)
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn handoff_and_pull_are_in_the_builtin_command_table() {
    assert_eq!(SlashCommand::from_str("handoff"), Ok(SlashCommand::Handoff));
    assert_eq!(SlashCommand::from_str("pull"), Ok(SlashCommand::Pull));

    let commands = built_in_slash_commands();
    assert!(commands.contains(&("handoff", SlashCommand::Handoff)));
    assert!(commands.contains(&("pull", SlashCommand::Pull)));
    assert_eq!(
        find_builtin_command("handoff", BuiltinCommandFlags::default()),
        Some(SlashCommand::Handoff)
    );
    assert_eq!(
        find_builtin_command("pull", BuiltinCommandFlags::default()),
        Some(SlashCommand::Pull)
    );

    assert!(
        SlashCommand::Handoff
            .description()
            .contains("qm handoff now")
    );
    assert!(SlashCommand::Pull.description().contains("qm handoff pull"));
    assert!(!SlashCommand::Handoff.available_during_task());
    assert!(!SlashCommand::Pull.available_during_task());
}

#[tokio::test]
async fn handoff_and_pull_dispatch_qm_handoff_shell_commands() {
    for (cmd, shell_command) in [
        (SlashCommand::Handoff, "qm handoff now"),
        (SlashCommand::Pull, "qm handoff pull"),
    ] {
        let (mut chat, mut rx, mut op_rx) = make_chatwidget_manual(/*model_override*/ None).await;
        chat.thread_id = Some(ThreadId::new());

        chat.dispatch_command(cmd);

        assert_eq!(next_shell_command(&mut op_rx), shell_command);
        assert_eq!(
            history_entries(&mut rx),
            vec![format!("/{}", cmd.command())]
        );
    }
}

#[tokio::test]
async fn typed_handoff_command_runs_qm_handoff_now_and_shows_its_output() {
    let (mut chat, mut rx, mut op_rx) = make_chatwidget_manual(/*model_override*/ None).await;
    chat.thread_id = Some(ThreadId::new());

    submit_composer_text(&mut chat, "/handoff");
    assert_eq!(next_shell_command(&mut op_rx), "qm handoff now");
    let _ = drain_insert_history(&mut rx);

    // The app server reports the command as a user-shell execution; the TUI renders it like `!`.
    handle_turn_started(&mut chat, "turn-handoff");
    let begin = begin_exec_with_source(
        &mut chat,
        "user-shell-handoff",
        "qm handoff now",
        ExecCommandSource::UserShell,
    );
    end_exec(
        &mut chat,
        begin,
        "handoff accepted: task-1\n",
        "",
        /*exit_code*/ 0,
    );
    handle_turn_completed(&mut chat, "turn-handoff", /*duration_ms*/ None);

    let rendered = rendered_history(&mut rx);
    assert!(rendered.contains("qm handoff now"), "{rendered}");
    assert!(rendered.contains("handoff accepted: task-1"), "{rendered}");
}

#[tokio::test]
async fn handoff_is_rejected_while_a_turn_is_running() {
    let (mut chat, mut rx, mut op_rx) = make_chatwidget_manual(/*model_override*/ None).await;
    chat.thread_id = Some(ThreadId::new());
    handle_turn_started(&mut chat, "turn-1");

    chat.dispatch_command(SlashCommand::Handoff);

    assert!(
        !std::iter::from_fn(|| op_rx.try_recv().ok())
            .any(|op| matches!(op, Op::RunUserShellCommand { .. }))
    );
    let rendered = rendered_history(&mut rx);
    assert!(
        rendered.contains("'/handoff' is disabled while a task is in progress."),
        "{rendered}"
    );
}

#[tokio::test]
async fn handoff_and_pull_are_rejected_in_remote_sessions_but_run_on_the_local_daemon() {
    for (is_local_daemon, cmd) in [
        (false, SlashCommand::Handoff),
        (false, SlashCommand::Pull),
        (true, SlashCommand::Handoff),
    ] {
        let (mut chat, mut rx, mut op_rx) = make_chatwidget_manual(/*model_override*/ None).await;
        chat.thread_id = Some(ThreadId::new());
        chat.remote_connection = Some(RemoteConnectionStatus {
            address: "ws://127.0.0.1:28472/".to_string(),
            version: "v0.158.0".to_string(),
            is_local_daemon,
        });

        chat.dispatch_command(cmd);

        if is_local_daemon {
            assert_eq!(next_shell_command(&mut op_rx), "qm handoff now");
        } else {
            assert!(
                !std::iter::from_fn(|| op_rx.try_recv().ok())
                    .any(|op| matches!(op, Op::RunUserShellCommand { .. }))
            );
            let rendered = rendered_history(&mut rx);
            assert!(
                rendered.contains(&format!(
                    "'/{}' is unavailable in remote sessions",
                    cmd.command()
                )),
                "{rendered}"
            );
        }
    }
}
