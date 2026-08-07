//! Locked dedicated system app roles (Wine pivot plan — excludes app_manager).

use std::str::FromStr;

/// NTW6 smoke requires these seven dedicated apps (app_manager is NTW5).
pub const SYSAPP_COUNT: usize = 7;

pub const DEDICATED_ROLES: &[DedicatedRole] = &[
    DedicatedRole::Settings,
    DedicatedRole::RunDialog,
    DedicatedRole::InstallerWizard,
    DedicatedRole::AppLibrary,
    DedicatedRole::CompatCenter,
    DedicatedRole::TaskManager,
    DedicatedRole::FileManager,
];

/// App Manager registry ids ↔ roles.
pub const ROLE_TO_APP_ID: &[(&str, &str)] = &[
    ("settings", "sys-settings"),
    ("run_dialog", "sys-run-dialog"),
    ("installer_wizard", "sys-installer-wizard"),
    ("app_library", "sys-app-library"),
    ("compat_center", "sys-compat-center"),
    ("task_manager", "sys-task-manager"),
    ("file_manager", "sys-file-manager"),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DedicatedRole {
    Settings,
    RunDialog,
    InstallerWizard,
    AppLibrary,
    CompatCenter,
    TaskManager,
    FileManager,
}

impl DedicatedRole {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Settings => "settings",
            Self::RunDialog => "run_dialog",
            Self::InstallerWizard => "installer_wizard",
            Self::AppLibrary => "app_library",
            Self::CompatCenter => "compat_center",
            Self::TaskManager => "task_manager",
            Self::FileManager => "file_manager",
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            Self::Settings => "Settings",
            Self::RunDialog => "Run Dialog",
            Self::InstallerWizard => "Installer Wizard",
            Self::AppLibrary => "App Library",
            Self::CompatCenter => "Compat Center",
            Self::TaskManager => "Task Manager",
            Self::FileManager => "File Manager",
        }
    }

    pub fn app_id(self) -> &'static str {
        match self {
            Self::Settings => "sys-settings",
            Self::RunDialog => "sys-run-dialog",
            Self::InstallerWizard => "sys-installer-wizard",
            Self::AppLibrary => "sys-app-library",
            Self::CompatCenter => "sys-compat-center",
            Self::TaskManager => "sys-task-manager",
            Self::FileManager => "sys-file-manager",
        }
    }

    /// Electron Hub tab id this role opens.
    pub fn hub_tab(self) -> &'static str {
        match self {
            Self::Settings => "sys-settings",
            Self::RunDialog => "sys-run",
            Self::InstallerWizard => "sys-installer",
            Self::AppLibrary => "sys-library",
            Self::CompatCenter => "sys-compat",
            Self::TaskManager => "sys-taskmgr",
            Self::FileManager => "sys-files",
        }
    }

    pub fn from_app_id(id: &str) -> Option<Self> {
        match id {
            "sys-settings" => Some(Self::Settings),
            "sys-run-dialog" => Some(Self::RunDialog),
            "sys-installer-wizard" => Some(Self::InstallerWizard),
            "sys-app-library" => Some(Self::AppLibrary),
            "sys-compat-center" => Some(Self::CompatCenter),
            "sys-task-manager" => Some(Self::TaskManager),
            "sys-file-manager" => Some(Self::FileManager),
            _ => None,
        }
    }
}

impl FromStr for DedicatedRole {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "settings" => Ok(Self::Settings),
            "run_dialog" | "run" => Ok(Self::RunDialog),
            "installer_wizard" | "installer" => Ok(Self::InstallerWizard),
            "app_library" | "library" => Ok(Self::AppLibrary),
            "compat_center" | "compat" => Ok(Self::CompatCenter),
            "task_manager" | "taskmgr" | "task" => Ok(Self::TaskManager),
            "file_manager" | "files" | "explorer" => Ok(Self::FileManager),
            other => Err(format!("unknown sysapp role: {other}")),
        }
    }
}
