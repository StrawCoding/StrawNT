use crate::entry::{AppEntry, AppRegistryFile};

pub const SCHEMA_VERSION: &str = "1.0";

pub fn validate_registry(registry: &AppRegistryFile) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();

    if registry.schema_version != SCHEMA_VERSION {
        errors.push(format!(
            "schema_version must be '{SCHEMA_VERSION}', got '{}'",
            registry.schema_version
        ));
    }

    let mut seen_ids = std::collections::HashSet::new();
    for (index, app) in registry.apps.iter().enumerate() {
        let prefix = format!("apps[{index}]");
        validate_entry(app, &prefix, &mut seen_ids, &mut errors);
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

fn validate_id(id: &str) -> bool {
    let mut chars = id.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if !first.is_ascii_lowercase() && !first.is_ascii_digit() {
        return false;
    }
    if id.len() > 64 {
        return false;
    }
    chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, '.' | '_' | '-'))
}

fn validate_entry(
    app: &AppEntry,
    prefix: &str,
    seen_ids: &mut std::collections::HashSet<String>,
    errors: &mut Vec<String>,
) {
    if !validate_id(&app.id) {
        errors.push(format!(
            "{prefix}.id '{}' does not match slug pattern",
            app.id
        ));
    } else if !seen_ids.insert(app.id.clone()) {
        errors.push(format!("{prefix}.id '{}' is duplicated", app.id));
    }

    if app.name.is_empty() || app.name.len() > 128 {
        errors.push(format!("{prefix}.name must be 1..=128 characters"));
    }

    if let Some(backend) = app.execution_backend {
        let _ = backend;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entry::{AppEntry, AppKind, AppSource};

    #[test]
    fn empty_registry_valid() {
        let registry = AppRegistryFile::default();
        assert!(validate_registry(&registry).is_ok());
    }

    #[test]
    fn duplicate_id_rejected() {
        let mut registry = AppRegistryFile::default();
        registry.apps.push(AppEntry::new(
            "demo",
            "Demo",
            AppKind::Win32,
            AppSource::Installer,
        ));
        registry.apps.push(AppEntry::new(
            "demo",
            "Demo 2",
            AppKind::Win32,
            AppSource::Installer,
        ));
        let err = validate_registry(&registry).unwrap_err();
        assert!(err.iter().any(|e| e.contains("duplicated")));
    }

    #[test]
    fn invalid_id_rejected() {
        let mut registry = AppRegistryFile::default();
        registry.apps.push(AppEntry::new(
            "Bad ID",
            "Bad",
            AppKind::Linux,
            AppSource::Manual,
        ));
        let err = validate_registry(&registry).unwrap_err();
        assert!(err.iter().any(|e| e.contains("slug pattern")));
    }

    #[test]
    fn valid_slug_accepted() {
        assert!(validate_id("notepad-plus"));
        assert!(validate_id("app.v2"));
        assert!(!validate_id("Bad"));
        assert!(!validate_id(""));
    }
}
