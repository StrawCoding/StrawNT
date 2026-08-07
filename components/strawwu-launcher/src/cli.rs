use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpenMode {
    /// Auto: installer heuristic → install+run, else run.
    Auto,
    /// Force run pipeline.
    Run,
    /// Force install registration + run pipeline.
    Install,
}

#[derive(Debug, Clone)]
pub enum Command {
    Run {
        binary: PathBuf,
        args: Vec<String>,
        backend: Option<String>,
        bundle: Vec<PathBuf>,
        profile: Option<PathBuf>,
    },
    /// File-manager / double-click entry: install and/or launch a Win32 file.
    Open {
        path: PathBuf,
        mode: OpenMode,
    },
    Install {
        installer: PathBuf,
    },
    /// Register MIME handler so .exe/.msi open with StrawNT on click.
    Integrate,
    Apps(AppsSubcommand),
    Devices(DevicesSubcommand),
    Mfp(MfpSubcommand),
    Profile(ProfileSubcommand),
    Repair {
        app_id: String,
    },
    Status,
    /// NTW1: vendored Proton-GE engine status / smoke helpers.
    Engine(EngineSubcommand),
    /// NTW1: engine doctor (pin + wine presence + honesty).
    Doctor { json: bool },
    /// NTW2: Wine prefix create / list.
    Prefix(PrefixSubcommand),
    /// NTW2: winetricks / repair recipes.
    Recipes(RecipesSubcommand),
    /// NTW2: honest compat matrix.
    Matrix(MatrixSubcommand),
    Config(ConfigSubcommand),
    Version,
    Help,
}

#[derive(Debug, Clone)]
pub enum PrefixSubcommand {
    Create {
        name: String,
        arch: String,
        force: bool,
        json: bool,
        home: Option<PathBuf>,
    },
    List {
        json: bool,
        home: Option<PathBuf>,
    },
}

#[derive(Debug, Clone)]
pub enum RecipesSubcommand {
    List { json: bool },
    Plan { id: String, json: bool },
    Apply {
        id: String,
        prefix: String,
        json: bool,
        home: Option<PathBuf>,
    },
}

#[derive(Debug, Clone)]
pub enum MatrixSubcommand {
    List { json: bool, home: Option<PathBuf> },
    Get {
        app_key: String,
        json: bool,
        home: Option<PathBuf>,
    },
    Set {
        name: String,
        status: String,
        notes: String,
        prefix: Option<String>,
        json: bool,
        home: Option<PathBuf>,
    },
    Seed { json: bool, home: Option<PathBuf> },
}

#[derive(Debug, Clone)]
pub enum EngineSubcommand {
    Status { json: bool },
    Hello { json: bool },
}

#[derive(Debug, Clone)]
pub enum ConfigSubcommand {
    Show,
    Set { key: String, value: String },
}

#[derive(Debug, Clone)]
pub enum AppsSubcommand {
    List,
}

#[derive(Debug, Clone)]
pub enum DevicesSubcommand {
    List { json: bool },
}

#[derive(Debug, Clone)]
pub enum MfpSubcommand {
    Smoke { json: bool },
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
        "open" => parse_open(&args[1..]),
        "install" => parse_install(&args[1..]),
        "integrate" | "desktop-integrate" => Ok(Command::Integrate),
        "apps" => parse_apps(&args[1..]),
        "devices" => parse_devices(&args[1..]),
        "mfp" => parse_mfp(&args[1..]),
        "profile" => parse_profile(&args[1..]),
        "repair" => {
            if args.len() < 2 {
                return Err("repair requires an app_id".into());
            }
            Ok(Command::Repair {
                app_id: args[1].clone(),
            })
        }
        "status" => Ok(Command::Status),
        "engine" => parse_engine(&args[1..]),
        "doctor" => parse_doctor(&args[1..]),
        "prefix" => parse_prefix(&args[1..]),
        "recipes" => parse_recipes(&args[1..]),
        "matrix" => parse_matrix(&args[1..]),
        "config" => parse_config(&args[1..]),
        "--version" | "version" => Ok(Command::Version),
        "--help" | "help" => Ok(Command::Help),
        _ => Err(format!("unknown command: {}", args[0])),
    }
}

fn parse_engine(args: &[String]) -> Result<Command, String> {
    let mut json = false;
    let mut sub = None;
    for a in args {
        match a.as_str() {
            "--json" => json = true,
            "status" => sub = Some("status"),
            "hello" => sub = Some("hello"),
            other => return Err(format!("unknown engine argument: {other}")),
        }
    }
    match sub {
        Some("hello") => Ok(Command::Engine(EngineSubcommand::Hello { json })),
        Some("status") | None => Ok(Command::Engine(EngineSubcommand::Status { json })),
        _ => Err("engine requires subcommand: status|hello".into()),
    }
}

fn parse_doctor(args: &[String]) -> Result<Command, String> {
    let mut json = false;
    for a in args {
        match a.as_str() {
            "--json" => json = true,
            other => return Err(format!("unknown doctor argument: {other}")),
        }
    }
    Ok(Command::Doctor { json })
}

fn take_flag_value(args: &[String], i: &mut usize, flag: &str) -> Result<Option<String>, String> {
    if args.get(*i).map(|s| s.as_str()) == Some(flag) {
        *i += 1;
        let v = args
            .get(*i)
            .cloned()
            .ok_or_else(|| format!("{flag} requires a value"))?;
        *i += 1;
        Ok(Some(v))
    } else {
        Ok(None)
    }
}

fn parse_home_json(args: &[String]) -> Result<(bool, Option<PathBuf>, Vec<String>), String> {
    let mut json = false;
    let mut home = None;
    let mut rest = Vec::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--json" {
            json = true;
            i += 1;
            continue;
        }
        if let Some(v) = take_flag_value(args, &mut i, "--home")? {
            home = Some(PathBuf::from(v));
            continue;
        }
        if let Some(v) = take_flag_value(args, &mut i, "-p")? {
            rest.push(format!("__prefix__:{v}"));
            continue;
        }
        if let Some(v) = take_flag_value(args, &mut i, "--prefix")? {
            rest.push(format!("__prefix__:{v}"));
            continue;
        }
        rest.push(args[i].clone());
        i += 1;
    }
    Ok((json, home, rest))
}

fn parse_prefix(args: &[String]) -> Result<Command, String> {
    if args.is_empty() {
        return Err("prefix requires subcommand: create|list".into());
    }
    match args[0].as_str() {
        "list" => {
            let (json, home, rest) = parse_home_json(&args[1..])?;
            if !rest.is_empty() {
                return Err(format!("unexpected prefix list args: {}", rest.join(" ")));
            }
            Ok(Command::Prefix(PrefixSubcommand::List { json, home }))
        }
        "create" => {
            let (json, home, rest) = parse_home_json(&args[1..])?;
            let mut name = None;
            let mut arch = "win64".to_string();
            let mut force = false;
            let mut i = 0;
            while i < rest.len() {
                match rest[i].as_str() {
                    "--force" => force = true,
                    "--arch" => {
                        i += 1;
                        arch = rest
                            .get(i)
                            .cloned()
                            .ok_or_else(|| "--arch requires a value".to_string())?;
                    }
                    other if !other.starts_with('-') && name.is_none() => {
                        name = Some(other.to_string());
                    }
                    other => return Err(format!("unexpected prefix create arg: {other}")),
                }
                i += 1;
            }
            let name = name.ok_or_else(|| "prefix create requires a name".to_string())?;
            Ok(Command::Prefix(PrefixSubcommand::Create {
                name,
                arch,
                force,
                json,
                home,
            }))
        }
        other => Err(format!("unknown prefix subcommand: {other}")),
    }
}

fn parse_recipes(args: &[String]) -> Result<Command, String> {
    if args.is_empty() {
        return Err("recipes requires subcommand: list|plan|apply".into());
    }
    match args[0].as_str() {
        "list" => {
            let (json, _home, rest) = parse_home_json(&args[1..])?;
            if !rest.is_empty() {
                return Err(format!("unexpected recipes list args: {}", rest.join(" ")));
            }
            Ok(Command::Recipes(RecipesSubcommand::List { json }))
        }
        "plan" => {
            let (json, _home, rest) = parse_home_json(&args[1..])?;
            let id = rest
                .first()
                .cloned()
                .ok_or_else(|| "recipes plan requires a recipe id".to_string())?;
            Ok(Command::Recipes(RecipesSubcommand::Plan { id, json }))
        }
        "apply" => {
            let (json, home, rest) = parse_home_json(&args[1..])?;
            let mut id = None;
            let mut prefix = None;
            for item in rest {
                if let Some(p) = item.strip_prefix("__prefix__:") {
                    prefix = Some(p.to_string());
                } else if id.is_none() {
                    id = Some(item);
                } else {
                    return Err(format!("unexpected recipes apply arg: {item}"));
                }
            }
            let id = id.ok_or_else(|| "recipes apply requires a recipe id".to_string())?;
            let prefix =
                prefix.ok_or_else(|| "recipes apply requires --prefix <name>".to_string())?;
            Ok(Command::Recipes(RecipesSubcommand::Apply {
                id,
                prefix,
                json,
                home,
            }))
        }
        other => Err(format!("unknown recipes subcommand: {other}")),
    }
}

fn parse_matrix(args: &[String]) -> Result<Command, String> {
    if args.is_empty() {
        return Err("matrix requires subcommand: list|get|set|seed".into());
    }
    match args[0].as_str() {
        "list" => {
            let (json, home, rest) = parse_home_json(&args[1..])?;
            if !rest.is_empty() {
                return Err(format!("unexpected matrix list args: {}", rest.join(" ")));
            }
            Ok(Command::Matrix(MatrixSubcommand::List { json, home }))
        }
        "get" => {
            let (json, home, rest) = parse_home_json(&args[1..])?;
            let app_key = rest
                .first()
                .cloned()
                .ok_or_else(|| "matrix get requires an app key".to_string())?;
            Ok(Command::Matrix(MatrixSubcommand::Get {
                app_key,
                json,
                home,
            }))
        }
        "set" => {
            let (json, home, rest) = parse_home_json(&args[1..])?;
            let mut name = None;
            let mut status = None;
            let mut notes = String::new();
            let mut prefix = None;
            let mut i = 0;
            while i < rest.len() {
                if let Some(p) = rest[i].strip_prefix("__prefix__:") {
                    prefix = Some(p.to_string());
                    i += 1;
                    continue;
                }
                match rest[i].as_str() {
                    "--notes" => {
                        i += 1;
                        notes = rest
                            .get(i)
                            .cloned()
                            .ok_or_else(|| "--notes requires a value".to_string())?;
                    }
                    "--status" => {
                        i += 1;
                        status = Some(
                            rest.get(i)
                                .cloned()
                                .ok_or_else(|| "--status requires a value".to_string())?,
                        );
                    }
                    other if !other.starts_with('-') && name.is_none() => {
                        name = Some(other.to_string());
                    }
                    other if !other.starts_with('-') && status.is_none() => {
                        status = Some(other.to_string());
                    }
                    other => return Err(format!("unexpected matrix set arg: {other}")),
                }
                i += 1;
            }
            let name = name.ok_or_else(|| "matrix set requires a name".to_string())?;
            let status = status.ok_or_else(|| "matrix set requires a status".to_string())?;
            Ok(Command::Matrix(MatrixSubcommand::Set {
                name,
                status,
                notes,
                prefix,
                json,
                home,
            }))
        }
        "seed" => {
            let (json, home, rest) = parse_home_json(&args[1..])?;
            if !rest.is_empty() {
                return Err(format!("unexpected matrix seed args: {}", rest.join(" ")));
            }
            Ok(Command::Matrix(MatrixSubcommand::Seed { json, home }))
        }
        other => Err(format!("unknown matrix subcommand: {other}")),
    }
}

fn parse_open(args: &[String]) -> Result<Command, String> {
    if args.is_empty() {
        return Err("open requires a file path (.exe / .msi)".into());
    }
    let mut mode = OpenMode::Auto;
    let mut path = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--install" => mode = OpenMode::Install,
            "--run" => mode = OpenMode::Run,
            "--auto" => mode = OpenMode::Auto,
            other => {
                if path.is_some() {
                    return Err(format!("unexpected argument for open: {other}"));
                }
                path = Some(PathBuf::from(other));
            }
        }
        i += 1;
    }
    let path = path.ok_or_else(|| "open requires a file path (.exe / .msi)".to_string())?;
    Ok(Command::Open { path, mode })
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

fn parse_devices(args: &[String]) -> Result<Command, String> {
    let mut json = false;
    let mut sub = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--json" => json = true,
            "list" => sub = Some("list"),
            other => return Err(format!("unknown devices argument: {other}")),
        }
        i += 1;
    }
    match sub {
        Some("list") | None => Ok(Command::Devices(DevicesSubcommand::List { json })),
        _ => Err("devices requires subcommand: list".into()),
    }
}

fn parse_mfp(args: &[String]) -> Result<Command, String> {
    let mut json = false;
    let mut sub = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--json" => json = true,
            "smoke" => sub = Some("smoke"),
            other => return Err(format!("unknown mfp argument: {other}")),
        }
        i += 1;
    }
    match sub {
        Some("smoke") | None => Ok(Command::Mfp(MfpSubcommand::Smoke { json })),
        _ => Err("mfp requires subcommand: smoke".into()),
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

fn parse_config(args: &[String]) -> Result<Command, String> {
    match args.first().map(|s| s.as_str()) {
        Some("show") | None => Ok(Command::Config(ConfigSubcommand::Show)),
        Some("set") => {
            if args.len() < 3 {
                return Err("config set requires <key> <value>".into());
            }
            Ok(Command::Config(ConfigSubcommand::Set {
                key: args[1].clone(),
                value: args[2].clone(),
            }))
        }
        Some(other) => Err(format!("unknown config subcommand: {other}")),
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
    fn parse_open_auto() {
        let cmd = parse_args(&args("open game.exe")).unwrap();
        match cmd {
            Command::Open { path, mode } => {
                assert_eq!(path, PathBuf::from("game.exe"));
                assert_eq!(mode, OpenMode::Auto);
            }
            _ => panic!("expected Open"),
        }
    }

    #[test]
    fn parse_open_install_flag() {
        let cmd = parse_args(&args("open --install setup.exe")).unwrap();
        match cmd {
            Command::Open { path, mode } => {
                assert_eq!(path, PathBuf::from("setup.exe"));
                assert_eq!(mode, OpenMode::Install);
            }
            _ => panic!("expected Open"),
        }
    }

    #[test]
    fn parse_integrate() {
        let cmd = parse_args(&args("integrate")).unwrap();
        assert!(matches!(cmd, Command::Integrate));
        let cmd2 = parse_args(&args("desktop-integrate")).unwrap();
        assert!(matches!(cmd2, Command::Integrate));
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

    #[test]
    fn parse_status() {
        let cmd = parse_args(&args("status")).unwrap();
        assert!(matches!(cmd, Command::Status));
    }

    #[test]
    fn parse_engine_status() {
        let cmd = parse_args(&args("engine status")).unwrap();
        assert!(matches!(
            cmd,
            Command::Engine(EngineSubcommand::Status { json: false })
        ));
        let cmd2 = parse_args(&args("engine status --json")).unwrap();
        assert!(matches!(
            cmd2,
            Command::Engine(EngineSubcommand::Status { json: true })
        ));
    }

    #[test]
    fn parse_doctor() {
        let cmd = parse_args(&args("doctor")).unwrap();
        assert!(matches!(cmd, Command::Doctor { json: false }));
        let cmd2 = parse_args(&args("doctor --json")).unwrap();
        assert!(matches!(cmd2, Command::Doctor { json: true }));
    }

    #[test]
    fn parse_prefix_create_list() {
        let cmd = parse_args(&args("prefix create demo --json")).unwrap();
        match cmd {
            Command::Prefix(PrefixSubcommand::Create {
                name,
                json: true,
                ..
            }) => assert_eq!(name, "demo"),
            _ => panic!("expected prefix create"),
        }
        let cmd2 = parse_args(&args("prefix list --json --home /tmp/x")).unwrap();
        match cmd2 {
            Command::Prefix(PrefixSubcommand::List {
                json: true,
                home: Some(h),
            }) => assert_eq!(h, PathBuf::from("/tmp/x")),
            _ => panic!("expected prefix list"),
        }
    }

    #[test]
    fn parse_recipes_and_matrix() {
        let cmd = parse_args(&args("recipes list --json")).unwrap();
        assert!(matches!(
            cmd,
            Command::Recipes(RecipesSubcommand::List { json: true })
        ));
        let cmd2 = parse_args(&args(
            "recipes apply fontsmooth --prefix demo --json",
        ))
        .unwrap();
        match cmd2 {
            Command::Recipes(RecipesSubcommand::Apply {
                id,
                prefix,
                json: true,
                ..
            }) => {
                assert_eq!(id, "fontsmooth");
                assert_eq!(prefix, "demo");
            }
            _ => panic!("expected recipes apply"),
        }
        let cmd3 = parse_args(&args("matrix seed --json")).unwrap();
        assert!(matches!(
            cmd3,
            Command::Matrix(MatrixSubcommand::Seed { json: true, .. })
        ));
    }

    #[test]
    fn parse_config_show() {
        let cmd = parse_args(&args("config")).unwrap();
        assert!(matches!(cmd, Command::Config(ConfigSubcommand::Show)));

        let cmd2 = parse_args(&args("config show")).unwrap();
        assert!(matches!(cmd2, Command::Config(ConfigSubcommand::Show)));
    }

    #[test]
    fn parse_config_set() {
        let cmd = parse_args(&args("config set backend container")).unwrap();
        match cmd {
            Command::Config(ConfigSubcommand::Set { key, value }) => {
                assert_eq!(key, "backend");
                assert_eq!(value, "container");
            }
            _ => panic!("expected Config Set"),
        }
    }

    #[test]
    fn parse_config_set_missing_value() {
        let result = parse_args(&args("config set onlykey"));
        assert!(result.is_err());
    }
}
