use std::path::PathBuf;

use crate::entry::{AppKind, AppSource, ExecutionBackend};

#[derive(Debug, Clone)]
pub enum Command {
    List { json: bool },
    Show { id: String, json: bool },
    Register {
        id: String,
        name: String,
        kind: AppKind,
        source: AppSource,
        install_path: Option<String>,
        protected: bool,
        backend: Option<ExecutionBackend>,
    },
    Remove {
        id: String,
        dry_run: bool,
        json: bool,
    },
    Validate { path: Option<PathBuf> },
    Version,
    Help,
}

pub fn parse_args(args: &[String]) -> Result<Command, String> {
    if args.is_empty() {
        return Ok(Command::Help);
    }

    let mut json = false;
    let mut dry_run = false;
    let mut positional = Vec::new();
    let mut i = 0;

    while i < args.len() {
        match args[i].as_str() {
            "--json" => json = true,
            "--dry-run" => dry_run = true,
            other => positional.push(other.to_string()),
        }
        i += 1;
    }

    if positional.is_empty() {
        return Ok(Command::Help);
    }

    match positional[0].as_str() {
        "list" => Ok(Command::List { json }),
        "show" => {
            if positional.len() < 2 {
                return Err("show requires an app id".into());
            }
            Ok(Command::Show {
                id: positional[1].clone(),
                json,
            })
        }
        "register" => parse_register(&positional[1..]),
        "remove" => {
            if positional.len() < 2 {
                return Err("remove requires an app id".into());
            }
            Ok(Command::Remove {
                id: positional[1].clone(),
                dry_run,
                json,
            })
        }
        "validate" => {
            let path = positional.get(1).map(PathBuf::from);
            Ok(Command::Validate { path })
        }
        "--version" | "version" => Ok(Command::Version),
        "--help" | "help" => Ok(Command::Help),
        other => Err(format!("unknown command: {other}")),
    }
}

fn parse_register(args: &[String]) -> Result<Command, String> {
    let mut id = None;
    let mut name = None;
    let mut kind = AppKind::Win32;
    let mut source = AppSource::Installer;
    let mut install_path = None;
    let mut protected = false;
    let mut backend = None;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--id" => {
                i += 1;
                id = Some(next_value(args, &mut i, "--id")?);
            }
            "--name" => {
                i += 1;
                name = Some(next_value(args, &mut i, "--name")?);
            }
            "--kind" => {
                i += 1;
                kind = parse_kind(&next_value(args, &mut i, "--kind")?)?;
            }
            "--source" => {
                i += 1;
                source = parse_source(&next_value(args, &mut i, "--source")?)?;
            }
            "--install-path" => {
                i += 1;
                install_path = Some(next_value(args, &mut i, "--install-path")?);
            }
            "--protected" => protected = true,
            "--backend" => {
                i += 1;
                backend = Some(parse_backend(&next_value(args, &mut i, "--backend")?)?);
            }
            other => return Err(format!("unknown register flag: {other}")),
        }
        i += 1;
    }

    Ok(Command::Register {
        id: id.ok_or("register requires --id")?,
        name: name.ok_or("register requires --name")?,
        kind,
        source,
        install_path,
        protected,
        backend,
    })
}

fn next_value(args: &[String], index: &mut usize, flag: &str) -> Result<String, String> {
    if *index >= args.len() {
        return Err(format!("{flag} requires a value"));
    }
    let value = args[*index].clone();
    Ok(value)
}

fn parse_kind(raw: &str) -> Result<AppKind, String> {
    match raw {
        "win32" => Ok(AppKind::Win32),
        "linux" => Ok(AppKind::Linux),
        "flatpak" => Ok(AppKind::Flatpak),
        "native" => Ok(AppKind::Native),
        other => Err(format!("invalid kind: {other}")),
    }
}

fn parse_source(raw: &str) -> Result<AppSource, String> {
    match raw {
        "installer" => Ok(AppSource::Installer),
        "launcher" => Ok(AppSource::Launcher),
        "flatpak" => Ok(AppSource::Flatpak),
        "seed" => Ok(AppSource::Seed),
        "manual" => Ok(AppSource::Manual),
        other => Err(format!("invalid source: {other}")),
    }
}

fn parse_backend(raw: &str) -> Result<ExecutionBackend, String> {
    match raw {
        "native" => Ok(ExecutionBackend::Native),
        "container" => Ok(ExecutionBackend::Container),
        "microvm" => Ok(ExecutionBackend::Microvm),
        other => Err(format!("invalid backend: {other}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(s: &str) -> Vec<String> {
        s.split_whitespace().map(|w| w.to_string()).collect()
    }

    #[test]
    fn parse_list() {
        let cmd = parse_args(&args("list --json")).unwrap();
        assert!(matches!(cmd, Command::List { json: true }));
    }

    #[test]
    fn parse_register_flags() {
        let cmd = parse_args(&args(
            "register --id demo --name Demo --kind win32 --source installer --install-path /opt/demo",
        ))
        .unwrap();
        match cmd {
            Command::Register {
                id,
                name,
                kind,
                source,
                install_path,
                ..
            } => {
                assert_eq!(id, "demo");
                assert_eq!(name, "Demo");
                assert_eq!(kind, AppKind::Win32);
                assert_eq!(source, AppSource::Installer);
                assert_eq!(install_path.as_deref(), Some("/opt/demo"));
            }
            _ => panic!("expected Register"),
        }
    }

    #[test]
    fn parse_remove_dry_run() {
        let cmd = parse_args(&args("remove demo --dry-run")).unwrap();
        match cmd {
            Command::Remove { id, dry_run, .. } => {
                assert_eq!(id, "demo");
                assert!(dry_run);
            }
            _ => panic!("expected Remove"),
        }
    }
}
