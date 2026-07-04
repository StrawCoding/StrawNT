use std::path::PathBuf;

#[derive(Debug, Clone)]
pub enum Command {
    Run {
        binary: PathBuf,
        args: Vec<String>,
        backend: Option<String>,
        bundle: Vec<PathBuf>,
        profile: Option<PathBuf>,
    },
    Install {
        installer: PathBuf,
    },
    Apps(AppsSubcommand),
    Profile(ProfileSubcommand),
    Repair {
        app_id: String,
    },
    Version,
    Help,
}

#[derive(Debug, Clone)]
pub enum AppsSubcommand {
    List,
}

#[derive(Debug, Clone)]
pub enum ProfileSubcommand {
    Inspect { app_id: String },
    Export { app_id: String },
}

pub fn parse_args(args: &[String]) -> Result<Command, String> {
    if args.is_empty() {
        return Ok(Command::Help);
    }

    match args[0].as_str() {
        "run" => parse_run(&args[1..]),
        "install" => parse_install(&args[1..]),
        "apps" => parse_apps(&args[1..]),
        "profile" => parse_profile(&args[1..]),
        "repair" => {
            if args.len() < 2 {
                return Err("repair requires an app_id".into());
            }
            Ok(Command::Repair {
                app_id: args[1].clone(),
            })
        }
        "--version" | "version" => Ok(Command::Version),
        "--help" | "help" => Ok(Command::Help),
        _ => Err(format!("unknown command: {}", args[0])),
    }
}

fn parse_run(args: &[String]) -> Result<Command, String> {
    if args.is_empty() {
        return Err("run requires a binary path".into());
    }

    let mut binary = PathBuf::new();
    let mut backend = None;
    let mut bundle = Vec::new();
    let mut profile = None;
    let mut app_args = Vec::new();
    let mut i = 0;

    while i < args.len() {
        match args[i].as_str() {
            "--backend" => {
                i += 1;
                if i >= args.len() {
                    return Err("--backend requires a value".into());
                }
                backend = Some(args[i].clone());
            }
            "--bundle" => {
                i += 1;
                if i >= args.len() {
                    return Err("--bundle requires comma-separated paths".into());
                }
                bundle = args[i].split(',').map(PathBuf::from).collect();
            }
            "--profile" => {
                i += 1;
                if i >= args.len() {
                    return Err("--profile requires a path".into());
                }
                profile = Some(PathBuf::from(&args[i]));
            }
            "--" => {
                app_args.extend(args[i + 1..].iter().cloned());
                break;
            }
            other => {
                if binary.as_os_str().is_empty() {
                    binary = PathBuf::from(other);
                } else {
                    app_args.push(other.to_string());
                }
            }
        }
        i += 1;
    }

    if binary.as_os_str().is_empty() {
        return Err("run requires a binary path".into());
    }

    Ok(Command::Run {
        binary,
        args: app_args,
        backend,
        bundle,
        profile,
    })
}

fn parse_install(args: &[String]) -> Result<Command, String> {
    if args.is_empty() {
        return Err("install requires an installer path".into());
    }
    Ok(Command::Install {
        installer: PathBuf::from(&args[0]),
    })
}

fn parse_apps(args: &[String]) -> Result<Command, String> {
    match args.first().map(|s| s.as_str()) {
        Some("list") | None => Ok(Command::Apps(AppsSubcommand::List)),
        Some(other) => Err(format!("unknown apps subcommand: {other}")),
    }
}

fn parse_profile(args: &[String]) -> Result<Command, String> {
    if args.is_empty() {
        return Err("profile requires a subcommand (inspect/export)".into());
    }
    match args[0].as_str() {
        "inspect" => {
            if args.len() < 2 {
                return Err("profile inspect requires an app_id".into());
            }
            Ok(Command::Profile(ProfileSubcommand::Inspect {
                app_id: args[1].clone(),
            }))
        }
        "export" => {
            if args.len() < 2 {
                return Err("profile export requires an app_id".into());
            }
            Ok(Command::Profile(ProfileSubcommand::Export {
                app_id: args[1].clone(),
            }))
        }
        other => Err(format!("unknown profile subcommand: {other}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(s: &str) -> Vec<String> {
        s.split_whitespace().map(|w| w.to_string()).collect()
    }

    #[test]
    fn parse_run_simple() {
        let cmd = parse_args(&args("run game.exe")).unwrap();
        match cmd {
            Command::Run { binary, backend, .. } => {
                assert_eq!(binary, PathBuf::from("game.exe"));
                assert!(backend.is_none());
            }
            _ => panic!("expected Run"),
        }
    }

    #[test]
    fn parse_run_with_backend() {
        let cmd = parse_args(&args("run --backend container untrusted.exe")).unwrap();
        match cmd {
            Command::Run { binary, backend, .. } => {
                assert_eq!(binary, PathBuf::from("untrusted.exe"));
                assert_eq!(backend, Some("container".into()));
            }
            _ => panic!("expected Run"),
        }
    }

    #[test]
    fn parse_run_with_bundle() {
        let cmd = parse_args(&args("run --bundle launcher.exe,game.exe launcher.exe")).unwrap();
        match cmd {
            Command::Run { bundle, .. } => {
                assert_eq!(bundle.len(), 2);
            }
            _ => panic!("expected Run"),
        }
    }

    #[test]
    fn parse_install() {
        let cmd = parse_args(&args("install setup.exe")).unwrap();
        match cmd {
            Command::Install { installer } => {
                assert_eq!(installer, PathBuf::from("setup.exe"));
            }
            _ => panic!("expected Install"),
        }
    }

    #[test]
    fn parse_version() {
        let cmd = parse_args(&args("--version")).unwrap();
        assert!(matches!(cmd, Command::Version));
    }

    #[test]
    fn empty_args_help() {
        let cmd = parse_args(&[]).unwrap();
        assert!(matches!(cmd, Command::Help));
    }

    #[test]
    fn unknown_command_error() {
        let result = parse_args(&args("invalid"));
        assert!(result.is_err());
    }
}
