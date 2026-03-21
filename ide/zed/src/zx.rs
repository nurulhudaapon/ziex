use std::path::Path;
use zed_extension_api::{self as zed, serde_json, settings::LspSettings, LanguageServerId, Result};

const ZIG_TEST_EXE_BASENAME: &str = "zig_test";

struct ZxExtension;

impl zed::Extension for ZxExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let (platform, _) = zed::current_platform();
        let env = match platform {
            zed::Os::Mac | zed::Os::Linux => worktree.shell_env(),
            zed::Os::Windows => vec![],
        };

        // Respect custom binary path from LSP settings
        if let Ok(lsp_settings) = LspSettings::for_worktree("zls", worktree) {
            if let Some(binary) = lsp_settings.binary {
                if let Some(path) = binary.path {
                    return Ok(zed::Command {
                        command: path,
                        args: binary.arguments.unwrap_or_default(),
                        env,
                    });
                }
            }
        }

        // Use zls from PATH (provided by the Zig extension)
        let path = worktree
            .which("zls")
            .ok_or("zls not found. Install the Zig extension or add zls to your PATH.")?;

        Ok(zed::Command { command: path, args: vec![], env })
    }

    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        let settings = LspSettings::for_worktree("zls", worktree)
            .ok()
            .and_then(|lsp_settings| lsp_settings.settings.clone())
            .unwrap_or_default();
        Ok(Some(settings))
    }

    fn dap_locator_create_scenario(
        &mut self,
        locator_name: String,
        build_task: zed::TaskTemplate,
        resolved_label: String,
        debug_adapter_name: String,
    ) -> Option<zed::DebugScenario> {
        if build_task.command != "zig" {
            return None;
        }

        let cwd = build_task.cwd.clone();
        let env = build_task.env.clone().into_iter().collect();

        let mut args_it = build_task.args.iter();
        let template = match args_it.next() {
            Some(arg) if arg == "build" => match args_it.next() {
                Some(arg) if arg == "run" => zed::BuildTaskTemplate {
                    label: "zig build".into(),
                    command: "zig".into(),
                    args: vec!["build".into()],
                    env,
                    cwd,
                },
                _ => return None,
            },
            Some(arg) if arg == "test" => {
                let test_exe_path = get_test_exe_path().unwrap();
                let mut args: Vec<String> = build_task
                    .args
                    .into_iter()
                    .map(|s| s.replace("\"", "'"))
                    .collect();
                args.push("--test-no-exec".into());
                args.push(format!("-femit-bin={test_exe_path}"));

                zed::BuildTaskTemplate {
                    label: "zig test --test-no-exec".into(),
                    command: "zig".into(),
                    args,
                    env,
                    cwd,
                }
            }
            _ => return None,
        };

        let config = serde_json::Value::Null;
        let Ok(config) = serde_json::to_string(&config) else {
            return None;
        };

        Some(zed::DebugScenario {
            adapter: debug_adapter_name,
            label: resolved_label.clone(),
            config,
            tcp_connection: None,
            build: Some(zed::BuildTaskDefinition::Template(
                zed::BuildTaskDefinitionTemplatePayload {
                    template,
                    locator_name: Some(locator_name.into()),
                },
            )),
        })
    }

    fn run_dap_locator(
        &mut self,
        _locator_name: String,
        build_task: zed::TaskTemplate,
    ) -> Result<zed::DebugRequest, String> {
        let mut args_it = build_task.args.iter();
        match args_it.next() {
            Some(arg) if arg == "build" => {
                let exec = get_project_name(&build_task).ok_or("Failed to get project name")?;
                Ok(zed::DebugRequest::Launch(zed::LaunchRequest {
                    program: format!("zig-out/bin/{exec}"),
                    cwd: build_task.cwd,
                    args: vec![],
                    envs: build_task.env.into_iter().collect(),
                }))
            }
            Some(arg) if arg == "test" => {
                let program = build_task
                    .args
                    .iter()
                    .find_map(|arg| {
                        arg.strip_prefix("-femit-bin=").map(|arg| {
                            arg.split("=")
                                .nth(1)
                                .ok_or("Expected binary path in -femit-bin=")
                                .map(|path| path.trim_end_matches(".exe"))
                        })
                    })
                    .ok_or("Failed to extract binary path from command args")
                    .flatten()?
                    .to_string();
                Ok(zed::DebugRequest::Launch(zed::LaunchRequest {
                    program,
                    cwd: build_task.cwd,
                    args: vec![],
                    envs: build_task.env.into_iter().collect(),
                }))
            }
            _ => Err("Unsupported build task".into()),
        }
    }
}

fn get_project_name(task: &zed::TaskTemplate) -> Option<String> {
    task.cwd
        .as_ref()
        .and_then(|cwd| Some(Path::new(&cwd).file_name()?.to_string_lossy().into_owned()))
}

fn get_test_exe_path() -> Option<String> {
    let test_exe_dir = std::env::current_dir().ok()?;
    let mut name = format!(
        "{}_{}",
        ZIG_TEST_EXE_BASENAME,
        uuid::Uuid::new_v4().to_string()
    );
    if zed::current_platform().0 == zed::Os::Windows {
        name.push_str(".exe");
    }
    Some(test_exe_dir.join(name).to_string_lossy().into_owned())
}

zed::register_extension!(ZxExtension);
