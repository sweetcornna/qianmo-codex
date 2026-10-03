// Copyright 2026 Qianmo AgentNest Team
// SPDX-License-Identifier: Apache-2.0

//! Qianmo entries in the embedded `defaults.toml` layer and how user config merges over them.

use super::tests::TestFileSystem;
use super::*;
use pretty_assertions::assert_eq;
use tempfile::tempdir;

async fn effective_config_with_user_toml(user_toml: Option<&str>) -> TomlValue {
    let codex_home = tempdir().expect("tempdir");
    if let Some(user_toml) = user_toml {
        std::fs::write(codex_home.path().join(CONFIG_TOML_FILE), user_toml)
            .expect("write user config");
    }
    load_config_layers_state(
        &TestFileSystem,
        codex_home.path(),
        /*cwd*/ None,
        &[],
        LoaderOverrides::without_managed_config_for_tests(),
        &crate::NoopThreadConfigLoader,
    )
    .await
    .expect("load config layers")
    .effective_config()
}

fn string_array(items: &[&str]) -> TomlValue {
    TomlValue::Array(
        items
            .iter()
            .map(|item| TomlValue::String((*item).to_string()))
            .collect(),
    )
}

fn table_entry<'a>(config: &'a TomlValue, path: &[&str]) -> Option<&'a TomlValue> {
    path.iter()
        .try_fold(config, |value, key| value.as_table()?.get(*key))
}

#[tokio::test]
async fn embedded_defaults_include_qianmo_handoff_entries() {
    let config = effective_config_with_user_toml(/*user_toml*/ None).await;

    assert_eq!(
        table_entry(&config, &["notify"]),
        Some(&string_array(&[
            "qm", "handoff", "sync", "--hook", "qmcode"
        ]))
    );
    assert_eq!(
        table_entry(&config, &["mcp_servers", "qianmo"]),
        Some(&TomlValue::Table(toml::toml! {
            command = "qm"
            args = ["handoff", "mcp"]
            env_vars = ["QMCODE_HOME"]
        }))
    );
    // MCP servers start with a filtered environment; the typed config must forward
    // QMCODE_HOME so `qm handoff mcp` sees a custom state directory.
    let server: crate::McpServerConfig = table_entry(&config, &["mcp_servers", "qianmo"])
        .expect("built-in qianmo MCP server")
        .clone()
        .try_into()
        .expect("built-in qianmo MCP server parses");
    let crate::McpServerTransportConfig::Stdio { env_vars, .. } = server.transport else {
        panic!("built-in qianmo MCP server must use stdio");
    };
    assert_eq!(
        env_vars,
        vec![crate::McpServerEnvVar::Name("QMCODE_HOME".to_string())]
    );
    assert_eq!(
        table_entry(&config, &["check_for_update_on_startup"]),
        Some(&TomlValue::Boolean(false))
    );
}

#[tokio::test]
async fn user_config_disables_qianmo_mcp_by_key_and_replaces_notify() {
    let config = effective_config_with_user_toml(Some(
        r#"
notify = ["my-notifier", "--flag"]

[mcp_servers.qianmo]
enabled = false
"#,
    ))
    .await;

    // Arrays replace the built-in value as a whole.
    assert_eq!(
        table_entry(&config, &["notify"]),
        Some(&string_array(&["my-notifier", "--flag"]))
    );
    // Tables merge key by key: `command`, `args` and `env_vars` still come from the built-in layer.
    assert_eq!(
        table_entry(&config, &["mcp_servers", "qianmo"]),
        Some(&TomlValue::Table(toml::toml! {
            command = "qm"
            args = ["handoff", "mcp"]
            env_vars = ["QMCODE_HOME"]
            enabled = false
        }))
    );
}
