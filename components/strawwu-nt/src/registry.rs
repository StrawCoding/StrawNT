use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RegistryHive {
    HKLM,
    HKCU,
    HKCR,
    HKU,
}

impl RegistryHive {
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_uppercase().as_str() {
            "HKLM" | "HKEY_LOCAL_MACHINE" => Some(Self::HKLM),
            "HKCU" | "HKEY_CURRENT_USER" => Some(Self::HKCU),
            "HKCR" | "HKEY_CLASSES_ROOT" => Some(Self::HKCR),
            "HKU" | "HKEY_USERS" => Some(Self::HKU),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum RegistryValue {
    String(String),
    Dword(u32),
    Qword(u64),
    Binary(Vec<u8>),
    MultiString(Vec<String>),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegistryOverlay {
    pub base_hive: RegistryHive,
    pub overlay_prefix: String,
    pub overrides: HashMap<String, HashMap<String, RegistryValue>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtualRegistry {
    hives: HashMap<RegistryHive, HashMap<String, HashMap<String, RegistryValue>>>,
    overlays: Vec<RegistryOverlay>,
}

impl VirtualRegistry {
    pub fn new() -> Self {
        let mut reg = Self {
            hives: HashMap::new(),
            overlays: Vec::new(),
        };
        reg.populate_defaults();
        reg
    }

    fn populate_defaults(&mut self) {
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "ProductName",
            RegistryValue::String("StrawWU Compatibility Layer".into()),
        );
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "CurrentBuild",
            RegistryValue::String("19045".into()),
        );
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "CurrentMajorVersionNumber",
            RegistryValue::Dword(10),
        );
        self.set(
            RegistryHive::HKLM,
            r"SYSTEM\CurrentControlSet\Services",
            "_placeholder",
            RegistryValue::String("virtual-services-hive".into()),
        );

        // DirectX
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\DirectX",
            "Version",
            RegistryValue::String("4.09.00.0904".into()),
        );
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\DirectX",
            "InstalledVersion",
            RegistryValue::Binary(vec![0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x00]),
        );

        // Visual C++ Redistributable
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64",
            "Installed",
            RegistryValue::Dword(1),
        );
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64",
            "Major",
            RegistryValue::Dword(14),
        );
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64",
            "Minor",
            RegistryValue::Dword(38),
        );

        // .NET Framework
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full",
            "Release",
            RegistryValue::Dword(528049),
        );
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full",
            "Version",
            RegistryValue::String("4.8.04084".into()),
        );

        // Installed components marker
        self.set(
            RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\Active Setup\Installed Components\{44BBA840-CC51-11CF-AAFA-00AA00B6015C}",
            "ComponentID",
            RegistryValue::String("Microsoft Outlook Express".into()),
        );

        // HKCU defaults
        self.set(
            RegistryHive::HKCU,
            r"Software\Microsoft\Windows\CurrentVersion\Explorer",
            "ShellState",
            RegistryValue::Binary(vec![0x24, 0x00, 0x00, 0x00]),
        );
        self.set(
            RegistryHive::HKCU,
            r"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
            "HideFileExt",
            RegistryValue::Dword(1),
        );
    }

    pub fn set(&mut self, hive: RegistryHive, key: &str, value_name: &str, value: RegistryValue) {
        let hive_map = self.hives.entry(hive).or_default();
        let key_map = hive_map.entry(key.to_string()).or_default();
        key_map.insert(value_name.to_string(), value);
    }

    pub fn get(&self, hive: &RegistryHive, key: &str, value_name: &str) -> Option<&RegistryValue> {
        self.hives
            .get(hive)
            .and_then(|h| h.get(key))
            .and_then(|k| k.get(value_name))
    }

    pub fn delete_value(&mut self, hive: &RegistryHive, key: &str, value_name: &str) -> bool {
        if let Some(h) = self.hives.get_mut(hive) {
            if let Some(k) = h.get_mut(key) {
                return k.remove(value_name).is_some();
            }
        }
        false
    }

    pub fn key_exists(&self, hive: &RegistryHive, key: &str) -> bool {
        self.hives.get(hive).map_or(false, |h| h.contains_key(key))
    }

    pub fn enumerate_values(&self, hive: &RegistryHive, key: &str) -> Vec<String> {
        self.hives
            .get(hive)
            .and_then(|h| h.get(key))
            .map(|k| k.keys().cloned().collect())
            .unwrap_or_default()
    }

    pub fn enumerate_subkeys(&self, hive: &RegistryHive, key: &str) -> Vec<String> {
        let prefix = if key.is_empty() {
            String::new()
        } else {
            format!(r"{}\", key)
        };

        let mut subkeys: Vec<String> = Vec::new();

        if let Some(hive_map) = self.hives.get(hive) {
            for existing_key in hive_map.keys() {
                if let Some(rest) = existing_key.strip_prefix(&prefix) {
                    let immediate = rest.split('\\').next().unwrap_or("");
                    if !immediate.is_empty() {
                        let subkey = immediate.to_string();
                        if !subkeys.contains(&subkey) {
                            subkeys.push(subkey);
                        }
                    }
                }
            }
        }

        subkeys.sort();
        subkeys
    }

    pub fn delete_key(&mut self, hive: &RegistryHive, key: &str) -> bool {
        if let Some(hive_map) = self.hives.get_mut(hive) {
            let prefix = format!(r"{}\", key);
            let keys_to_remove: Vec<String> = hive_map
                .keys()
                .filter(|k| *k == key || k.starts_with(&prefix))
                .cloned()
                .collect();

            if keys_to_remove.is_empty() {
                return false;
            }
            for k in &keys_to_remove {
                hive_map.remove(k);
            }
            true
        } else {
            false
        }
    }

    pub fn create_overlay(&mut self, base_hive: RegistryHive, overlay_prefix: &str) {
        self.overlays.push(RegistryOverlay {
            base_hive,
            overlay_prefix: overlay_prefix.to_string(),
            overrides: HashMap::new(),
        });
    }

    pub fn set_overlay(&mut self, overlay_index: usize, key: &str, value_name: &str, value: RegistryValue) -> bool {
        if let Some(overlay) = self.overlays.get_mut(overlay_index) {
            overlay.overrides
                .entry(key.to_string())
                .or_default()
                .insert(value_name.to_string(), value);
            true
        } else {
            false
        }
    }

    pub fn get_with_overlay(&self, hive: &RegistryHive, key: &str, value_name: &str) -> Option<&RegistryValue> {
        for overlay in self.overlays.iter().rev() {
            if overlay.base_hive == *hive && key.starts_with(&overlay.overlay_prefix) {
                if let Some(val) = overlay.overrides.get(key).and_then(|k| k.get(value_name)) {
                    return Some(val);
                }
            }
        }
        self.get(hive, key, value_name)
    }

    pub fn overlay_count(&self) -> usize {
        self.overlays.len()
    }
}

impl Default for VirtualRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registry_defaults_populated() {
        let reg = VirtualRegistry::new();
        let product = reg.get(
            &RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "ProductName",
        );
        assert!(product.is_some());
        if let Some(RegistryValue::String(s)) = product {
            assert!(s.contains("StrawWU"));
        }
    }

    #[test]
    fn registry_set_and_get() {
        let mut reg = VirtualRegistry::new();
        reg.set(RegistryHive::HKCU, r"Software\TestApp", "Setting1", RegistryValue::Dword(42));
        let val = reg.get(&RegistryHive::HKCU, r"Software\TestApp", "Setting1");
        assert_eq!(val, Some(&RegistryValue::Dword(42)));
    }

    #[test]
    fn registry_delete() {
        let mut reg = VirtualRegistry::new();
        reg.set(RegistryHive::HKCU, "key", "val", RegistryValue::Dword(1));
        assert!(reg.delete_value(&RegistryHive::HKCU, "key", "val"));
        assert!(reg.get(&RegistryHive::HKCU, "key", "val").is_none());
    }

    #[test]
    fn registry_enumerate() {
        let mut reg = VirtualRegistry::new();
        reg.set(RegistryHive::HKCU, "k", "a", RegistryValue::Dword(1));
        reg.set(RegistryHive::HKCU, "k", "b", RegistryValue::Dword(2));
        let vals = reg.enumerate_values(&RegistryHive::HKCU, "k");
        assert_eq!(vals.len(), 2);
    }

    #[test]
    fn hive_from_str() {
        assert_eq!(RegistryHive::from_str("HKLM"), Some(RegistryHive::HKLM));
        assert_eq!(RegistryHive::from_str("HKEY_CURRENT_USER"), Some(RegistryHive::HKCU));
        assert_eq!(RegistryHive::from_str("invalid"), None);
    }

    // Extended defaults tests

    #[test]
    fn registry_directx_populated() {
        let reg = VirtualRegistry::new();
        let ver = reg.get(
            &RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\DirectX",
            "Version",
        );
        assert!(matches!(ver, Some(RegistryValue::String(_))));
    }

    #[test]
    fn registry_vcredist_populated() {
        let reg = VirtualRegistry::new();
        let installed = reg.get(
            &RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64",
            "Installed",
        );
        assert_eq!(installed, Some(&RegistryValue::Dword(1)));
    }

    #[test]
    fn registry_dotnet_populated() {
        let reg = VirtualRegistry::new();
        let release = reg.get(
            &RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full",
            "Release",
        );
        assert_eq!(release, Some(&RegistryValue::Dword(528049)));
    }

    // enumerate_subkeys tests

    #[test]
    fn enumerate_subkeys_basic() {
        let reg = VirtualRegistry::new();
        let subkeys = reg.enumerate_subkeys(
            &RegistryHive::HKLM,
            r"SOFTWARE\Microsoft",
        );
        assert!(subkeys.contains(&"Windows NT".to_string()));
        assert!(subkeys.contains(&"DirectX".to_string()));
        assert!(subkeys.contains(&"VisualStudio".to_string()));
    }

    #[test]
    fn enumerate_subkeys_empty() {
        let reg = VirtualRegistry::new();
        let subkeys = reg.enumerate_subkeys(&RegistryHive::HKCR, r"NonExistent\Key");
        assert!(subkeys.is_empty());
    }

    #[test]
    fn enumerate_subkeys_custom() {
        let mut reg = VirtualRegistry::new();
        reg.set(RegistryHive::HKCU, r"App\Sub1", "v", RegistryValue::Dword(1));
        reg.set(RegistryHive::HKCU, r"App\Sub2", "v", RegistryValue::Dword(2));
        reg.set(RegistryHive::HKCU, r"App\Sub2\Deep", "v", RegistryValue::Dword(3));
        let subkeys = reg.enumerate_subkeys(&RegistryHive::HKCU, "App");
        assert!(subkeys.contains(&"Sub1".to_string()));
        assert!(subkeys.contains(&"Sub2".to_string()));
        assert_eq!(subkeys.len(), 2);
    }

    // delete_key tests

    #[test]
    fn delete_key_removes_key() {
        let mut reg = VirtualRegistry::new();
        reg.set(RegistryHive::HKCU, r"ToDelete", "val", RegistryValue::Dword(1));
        assert!(reg.key_exists(&RegistryHive::HKCU, "ToDelete"));
        assert!(reg.delete_key(&RegistryHive::HKCU, "ToDelete"));
        assert!(!reg.key_exists(&RegistryHive::HKCU, "ToDelete"));
    }

    #[test]
    fn delete_key_removes_subkeys() {
        let mut reg = VirtualRegistry::new();
        reg.set(RegistryHive::HKCU, r"Parent", "v", RegistryValue::Dword(1));
        reg.set(RegistryHive::HKCU, r"Parent\Child", "v", RegistryValue::Dword(2));
        reg.set(RegistryHive::HKCU, r"Parent\Child\GrandChild", "v", RegistryValue::Dword(3));
        assert!(reg.delete_key(&RegistryHive::HKCU, "Parent"));
        assert!(!reg.key_exists(&RegistryHive::HKCU, "Parent"));
        assert!(!reg.key_exists(&RegistryHive::HKCU, r"Parent\Child"));
        assert!(!reg.key_exists(&RegistryHive::HKCU, r"Parent\Child\GrandChild"));
    }

    #[test]
    fn delete_key_nonexistent_returns_false() {
        let mut reg = VirtualRegistry::new();
        assert!(!reg.delete_key(&RegistryHive::HKCU, "NoSuchKey"));
    }

    // Overlay tests

    #[test]
    fn overlay_basic() {
        let mut reg = VirtualRegistry::new();
        reg.create_overlay(RegistryHive::HKLM, r"SOFTWARE\MyApp");
        assert_eq!(reg.overlay_count(), 1);

        reg.set(RegistryHive::HKLM, r"SOFTWARE\MyApp\Config", "Theme", RegistryValue::String("dark".into()));
        reg.set_overlay(0, r"SOFTWARE\MyApp\Config", "Theme", RegistryValue::String("light".into()));

        let base_val = reg.get(&RegistryHive::HKLM, r"SOFTWARE\MyApp\Config", "Theme");
        assert_eq!(base_val, Some(&RegistryValue::String("dark".into())));

        let overlay_val = reg.get_with_overlay(&RegistryHive::HKLM, r"SOFTWARE\MyApp\Config", "Theme");
        assert_eq!(overlay_val, Some(&RegistryValue::String("light".into())));
    }

    #[test]
    fn overlay_falls_through_to_base() {
        let mut reg = VirtualRegistry::new();
        reg.create_overlay(RegistryHive::HKLM, r"SOFTWARE\MyApp");
        reg.set(RegistryHive::HKLM, r"SOFTWARE\MyApp\Config", "Lang", RegistryValue::String("en".into()));

        let val = reg.get_with_overlay(&RegistryHive::HKLM, r"SOFTWARE\MyApp\Config", "Lang");
        assert_eq!(val, Some(&RegistryValue::String("en".into())));
    }

    #[test]
    fn overlay_unrelated_key_not_affected() {
        let mut reg = VirtualRegistry::new();
        reg.create_overlay(RegistryHive::HKLM, r"SOFTWARE\MyApp");
        let val = reg.get_with_overlay(
            &RegistryHive::HKLM,
            r"SOFTWARE\Microsoft\DirectX",
            "Version",
        );
        assert!(val.is_some());
    }
}
