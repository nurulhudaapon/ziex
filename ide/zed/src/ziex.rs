use zed_extension_api::{
    self as zed, serde_json, settings::LspSettings, LanguageServerId, Result,
};

struct ZiexExtension {
    zx_module_path: Option<String>,
}

impl zed::Extension for ZiexExtension {
    fn new() -> Self {
        Self {
            zx_module_path: None,
        }
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
        if let Ok(lsp_settings) = LspSettings::for_worktree("zxls", worktree) {
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

        let zig_path = worktree.which("zig");
        let build_file = format!("{}/build.zig", worktree.root_path());

        // Resolve project ZX_MODULE_PATH via `zig build zx -- env` when possible.
        self.zx_module_path = zig_path
            .as_ref()
            .and_then(|zig| read_zx_module_path(zig, &build_file, worktree).ok().flatten());

        // Prefer installed `zx lsp` only when we know the module path; otherwise
        // `zx lsp` starts without `@import("zx")` resolution (see empty `modules`).
        if let (Some(zx_path), Some(module_path)) =
            (worktree.which("zx"), self.zx_module_path.clone())
        {
            let mut env = env;
            env.push(("ZX_MODULE_PATH".into(), module_path.clone()));
            return Ok(zed::Command {
                command: zx_path,
                args: vec![
                    "lsp".into(),
                    "--zx-module".into(),
                    module_path,
                ],
                env,
            });
        }

        // Fallback: `zig build zx -- lsp` — the zx run step injects ZX_MODULE_PATH.
        let zig_path = zig_path.ok_or("Neither zx (with resolvable ZX_MODULE_PATH) nor zig found.")?;
        Ok(zed::Command {
            command: zig_path,
            args: vec![
                "build".into(),
                "--build-file".into(),
                build_file,
                "-Dziex-lsp=true".into(),
                "--release=fast".into(),
                "zx".into(),
                "--".into(),
                "lsp".into(),
            ],
            env,
        })
    }

    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<serde_json::Value>> {
        let mut settings = LspSettings::for_worktree("zxls", worktree)
            .ok()
            .and_then(|lsp_settings| lsp_settings.settings.clone())
            .unwrap_or_else(|| serde_json::json!({}));

        if self.zx_module_path.is_none() {
            if let Some(zig) = worktree.which("zig") {
                let build_file = format!("{}/build.zig", worktree.root_path());
                self.zx_module_path = read_zx_module_path(&zig, &build_file, worktree)
                    .ok()
                    .flatten();
            }
        }

        if let Some(module_path) = &self.zx_module_path {
            if let Some(obj) = settings.as_object_mut() {
                obj.entry("import_extensions")
                    .or_insert_with(|| serde_json::json!(["zx"]));
                obj.insert(
                    "modules".into(),
                    serde_json::json!([{ "name": "zx", "path": module_path }]),
                );
            }
        }

        if settings.as_object().map(|o| o.is_empty()).unwrap_or(true) {
            return Ok(None);
        }
        Ok(Some(settings))
    }
}

fn read_zx_module_path(
    zig: &str,
    build_file: &str,
    worktree: &zed::Worktree,
) -> Result<Option<String>> {
    let output = zed::process::Command::new(zig)
        .arg("build")
        .arg("--build-file")
        .arg(build_file)
        .arg("zx")
        .arg("--")
        .arg("env")
        .arg("--fmt=json")
        .envs(worktree.shell_env())
        .output()
        .map_err(|e| format!("failed to run zig build zx -- env: {e}"))?;

    if output.status != Some(0) {
        return Ok(None);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    parse_zx_module_path_json(&stdout)
}

fn parse_zx_module_path_json(stdout: &str) -> Result<Option<String>> {
    let Some(start) = stdout.find('{') else {
        return Ok(None);
    };
    let Some(end) = stdout.rfind('}') else {
        return Ok(None);
    };
    if end < start {
        return Ok(None);
    }

    let value: serde_json::Value = serde_json::from_str(&stdout[start..=end])
        .map_err(|e| format!("failed to parse zx env JSON: {e}"))?;
    Ok(value
        .get("zx_module_path")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(str::to_owned))
}

zed::register_extension!(ZiexExtension);
