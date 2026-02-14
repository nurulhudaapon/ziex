use std::{fs, path::Path};
use zed_extension_api::{self as zed, serde_json, settings::LspSettings, LanguageServerId, Result};

const ZIG_TEST_EXE_BASENAME: &str = "zig_test";

struct ZxExtension {
    cached_binary_path: Option<String>,
}

#[derive(Clone)]
struct ZlsBinary {
    path: String,
    args: Option<Vec<String>>,
    environment: Option<Vec<(String, String)>>,
}

impl ZxExtension {
    fn language_server_binary(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<ZlsBinary> {
        let mut args: Option<Vec<String>> = None;

        let (platform, arch) = zed::current_platform();
        let environment = match platform {
            zed::Os::Mac | zed::Os::Linux => Some(worktree.shell_env()),
            zed::Os::Windows => None,
        };

        if let Ok(lsp_settings) = LspSettings::for_worktree("zls", worktree) {
            if let Some(binary) = lsp_settings.binary {
                args = binary.arguments;
                if let Some(path) = binary.path {
                    return Ok(ZlsBinary {
                        path: path.clone(),
                        args,
                        environment,
                    });
                }
            }
        }

        if let Some(path) = worktree.which("zls") {
            return Ok(ZlsBinary {
                path,
                args,
                environment,
            });
        }

        if let Some(path) = &self.cached_binary_path {
            if fs::metadata(path).map_or(false, |stat| stat.is_file()) {
                return Ok(ZlsBinary {
                    path: path.clone(),
                    args,
                    environment,
                });
            }
        }

        zed::set_language_server_installation_status(
            language_server_id,
            &zed::LanguageServerInstallationStatus::CheckingForUpdate,
        );

        // Note that in github releases and on zlstools.org the tar.gz asset is not shown
        // but is available at https://builds.zigtools.org/zls-{os}-{arch}-{version}.tar.gz
        let release = zed::latest_github_release(
            "zigtools/zls",
            zed::GithubReleaseOptions {
                require_assets: true,
                pre_release: false,
            },
        )?;

        let arch: &str = match arch {
            zed::Architecture::Aarch64 => "aarch64",
            zed::Architecture::X86 => "x86",
            zed::Architecture::X8664 => "x86_64",
        };

        let os: &str = match platform {
            zed::Os::Mac => "macos",
            zed::Os::Linux => "linux",
            zed::Os::Windows => "windows",
        };

        let extension: &str = match platform {
            zed::Os::Mac | zed::Os::Linux => "tar.gz",
            zed::Os::Windows => "zip",
        };

        let asset_name: String = format!("zls-{}-{}-{}.{}", arch, os, release.version, extension);
        let download_url = format!("https://builds.zigtools.org/{}", asset_name);

        let version_dir = format!("zls-{}", release.version);
        let binary_path = match platform {
            zed::Os::Mac | zed::Os::Linux => format!("{version_dir}/zls"),
            zed::Os::Windows => format!("{version_dir}/zls.exe"),
        };

        if !fs::metadata(&binary_path).map_or(false, |stat| stat.is_file()) {
            zed::set_language_server_installation_status(
                language_server_id,
                &zed::LanguageServerInstallationStatus::Downloading,
            );

            zed::download_file(
                &download_url,
                &version_dir,
                match platform {
                    zed::Os::Mac | zed::Os::Linux => zed::DownloadedFileType::GzipTar,
                    zed::Os::Windows => zed::DownloadedFileType::Zip,
                },
            )
            .map_err(|e| format!("failed to download file: {e}"))?;

            zed::make_file_executable(&binary_path)?;

            let entries =
                fs::read_dir(".").map_err(|e| format!("failed to list working directory {e}"))?;
            for entry in entries {
                let entry = entry.map_err(|e| format!("failed to load directory entry {e}"))?;
                if entry.file_name().to_str() != Some(&version_dir) {
                    fs::remove_dir_all(entry.path()).ok();
                }
            }
        }

        self.cached_binary_path = Some(binary_path.clone());
        Ok(ZlsBinary {
            path: binary_path,
            args,
            environment,
        })
    }
}

impl zed::Extension for ZxExtension {
    fn new() -> Self {
        Self {
            cached_binary_path: None,
        }
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let zls_binary = self.language_server_binary(language_server_id, worktree)?;
        Ok(zed::Command {
            command: zls_binary.path,
            args: zls_binary.args.unwrap_or_default(),
            env: zls_binary.environment.unwrap_or_default(),
        })
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
                    // TODO verify if this is required on non-Windows platforms
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
                // We only handle the default case where the binary name matches the project name.
                // This is valid for projects created with `zig init`.
                // In other cases, the user should provide a custom debug configuration.
                let exec = get_project_name(&build_task).ok_or("Failed to get project name")?;

                let request = zed::LaunchRequest {
                    program: format!("zig-out/bin/{exec}"),
                    cwd: build_task.cwd,
                    args: vec![],
                    envs: build_task.env.into_iter().collect(),
                };

                Ok(zed::DebugRequest::Launch(request))
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
                let request = zed::LaunchRequest {
                    program,
                    cwd: build_task.cwd,
                    args: vec![],
                    envs: build_task.env.into_iter().collect(),
                };
                Ok(zed::DebugRequest::Launch(request))
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
