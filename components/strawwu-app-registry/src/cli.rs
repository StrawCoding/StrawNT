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
        desktop_entry: Option<String>,
        protected: bool,
        backend: Option<ExecutionBackend>,
    },
    Remove {
        id: String,
        dry_run: bool,
        deep: bool,
        json: bool,
    },
    DeepRemove {
        id: String,
        dry_run: bool,
        json: bool,
    },
    RemoveByDesktop {
        desktop: String,
        dry_run: bool,
        deep: bool,
        json: bool,
    },
    Validate { path: Option<PathBuf> },
    Scan {
        linux: bool,
        flatpak: bool,
        all: bool,
        dry_run: bool,
        json: bool,
    },
    Version,
    Help,
}

pub fn parse_args(args: &[String]) -> Result<Command, String> {
    if args.is_empty() {
        return Ok(Command::Help);
    }

    let mut json = false;
    let mut dry_run = false;
    let mut deep = false;
    let mut scan_linux = false;
    let mut scan_flatpak = false;
    let mut scan_all = false;
    let mut positional = Vec::new();
    let mut i = 0;

    while i < args.len() {
        match args[i].as_str() {
            "--json" => json = true,
            "--dry-run" => dry_run = true,
            "--deep" => deep = true,
            "--linux" => scan_linux = true,
            "--flatpak" => scan_flatpak = true,
            "--all" => scan_all = true,
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
                deep,
                json,
            })
        }
        "deep-remove" => {
            if positional.len() < 2 {
                return Err("deep-remove requires an app id".into());
            }
            Ok(Command::DeepRemove {
                id: positional[1].clone(),
                dry_run,
                json,
            })
        }
        "remove-by-desktop" => {
            if positional.len() < 2 {
                return Err("remove-by-desktop requires a .desktop path".into());
            }
            Ok(Command::RemoveByDesktop {
                desktop: positional[1..].join(" "),
                dry_run,
                deep,
                json,
            })
        }
        "validate" => {
            let path = positional.get(1).map(PathBuf::from);
            Ok(Command::Validate { path })
        }
        "scan" => {
            let linux = scan_linux || scan_all;
            let flatpak = scan_flatpak || scan_all;
            let all = scan_all || (!linux && !flatpak);
            Ok(Command::Scan {
                linux: if all { true } else { linux },
                flatpak: if all { true } else { flatpak },
                all,
                dry_run,
                json,
            })
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
    let mut desktop_entry = None;
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
            "--desktop-entry" => {
                i += 1;
                desktop_entry = Some(next_value(args, &mut i, "--desktop-entry")?);
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
        desktop_entry,
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
    ExecutionBackend::from_str(raw)
        .ok_or_else(|| format!("invalid backend: {raw} (expected wine|native|container|microvm)"))
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
            desktop_entry,
            ..
        } => {
            assert_eq!(id, "demo");
            assert_eq!(name, "Demo");
            assert_eq!(kind, AppKind::Win32);
            assert_eq!(source, AppSource::Installer);
            assert_eq!(install_path.as_deref(), Some("/opt/demo"));
            assert_eq!(desktop_entry, None);
        }
            _ => panic!("expected Register"),
        }
    }

    #[test]
    fn parse_remove_deep_dry_run() {
        let cmd = parse_args(&args("remove demo --deep --dry-run")).unwrap();
        match cmd {
            Command::Remove { id, dry_run, deep, .. } => {
                assert_eq!(id, "demo");
                assert!(dry_run);
                assert!(deep);
            }
            _ => panic!("expected Remove"),
        }
    }

    #[test]
    fn parse_deep_remove() {
        let cmd = parse_args(&args("deep-remove demo --json")).unwrap();
        match cmd {
            Command::DeepRemove { id, json, .. } => {
                assert_eq!(id, "demo");
                assert!(json);
            }
            _ => panic!("expected DeepRemove"),
        }
    }

    #[test]
    fn parse_remove_dry_run() {
        let cmd = parse_args(&args("remove demo --dry-run")).unwrap();
        match cmd {
            Command::Remove { id, dry_run, deep, .. } => {
                assert_eq!(id, "demo");
                assert!(dry_run);
                assert!(!deep);
            }
            _ => panic!("expected Remove"),
        }
    }

    #[test]
    fn parse_remove_by_desktop() {
        let cmd = parse_args(&args("remove-by-desktop /tmp/foo.desktop --dry-run --json")).unwrap();
        match cmd {
            Command::RemoveByDesktop {
                desktop,
                dry_run,
                deep,
                json,
            } => {
                assert_eq!(desktop, "/tmp/foo.desktop");
                assert!(dry_run);
                assert!(!deep);
                assert!(json);
            }
            _ => panic!("expected RemoveByDesktop"),
        }
    }

    #[test]
    fn parse_scan_defaults_to_all() {
        let cmd = parse_args(&args("scan --json")).unwrap();
        match cmd {
            Command::Scan {
                linux,
                flatpak,
                all,
                json,
                ..
            } => {
                assert!(linux);
                assert!(flatpak);
                assert!(all);
                assert!(json);
            }
            _ => panic!("expected Scan"),
        }
    }

    #[test]
    fn parse_scan_linux_only() {
        let cmd = parse_args(&args("scan --linux")).unwrap();
        match cmd {
            Command::Scan {
                linux,
                flatpak,
                all,
                ..
            } => {
                assert!(linux);
                assert!(!flatpak);
                assert!(!all);
            }
            _ => panic!("expected Scan"),
        }
    }
}
