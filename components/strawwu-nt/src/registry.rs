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
pub struct VirtualRegistry {
    hives: HashMap<RegistryHive, HashMap<String, HashMap<String, RegistryValue>>>,
}

impl VirtualRegistry {
    pub fn new() -> Self {
        let mut reg = Self {
            hives: HashMap::new(),
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
}
