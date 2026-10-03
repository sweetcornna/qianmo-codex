// Copyright 2026 Qianmo AgentNest Team
// SPDX-License-Identifier: Apache-2.0

//! Embedded system skills must not steer their scripts or the model to the official
//! Codex state directory (`~/.codex`, `$CODEX_HOME`) or to the official `codex` binary.

use super::SYSTEM_SKILLS_DIR;
use include_dir::Dir;
use pretty_assertions::assert_eq;

const FORBIDDEN: &[&str] = &[
    "~/.codex",
    "$HOME/.codex",
    "$CODEX_HOME",
    "${CODEX_HOME",
    "\"CODEX_HOME\"",
    "codex mcp ",
    "codex plugin ",
];

fn collect_text_files<'a>(dir: &'a Dir<'a>, out: &mut Vec<(String, &'a str)>) {
    for file in dir.files() {
        if let Some(text) = file.contents_utf8() {
            out.push((file.path().display().to_string(), text));
        }
    }
    for child in dir.dirs() {
        collect_text_files(child, out);
    }
}

#[test]
fn embedded_system_skills_do_not_point_at_the_official_codex_home_or_binary() {
    let mut files = Vec::new();
    collect_text_files(&SYSTEM_SKILLS_DIR, &mut files);
    assert!(
        files
            .iter()
            .any(|(path, _)| path.ends_with("install-skill-from-github.py")),
        "expected the embedded skill-installer scripts"
    );

    let mut offending = Vec::new();
    for (path, text) in &files {
        for (index, line) in text.lines().enumerate() {
            for pattern in FORBIDDEN {
                if line.contains(pattern) {
                    offending.push(format!("{path}:{}: {pattern}", index + 1));
                }
            }
        }
    }
    assert_eq!(offending, Vec::<String>::new());
}

#[test]
fn skill_installer_scripts_default_to_the_qmcode_home() {
    for script in [
        "skill-installer/scripts/install-skill-from-github.py",
        "skill-installer/scripts/list-skills.py",
    ] {
        let text = SYSTEM_SKILLS_DIR
            .get_file(script)
            .and_then(|file| file.contents_utf8())
            .unwrap_or_else(|| panic!("{script} should be embedded"));
        assert!(
            text.contains(
                r#"return os.environ.get("QMCODE_HOME") or os.path.expanduser("~/.qmcode")"#
            ),
            "{script} must default to QMCODE_HOME, then ~/.qmcode"
        );
    }
}
