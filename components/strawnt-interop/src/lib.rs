//! StrawNT Win32 IPC interop (NTW4).
//!
//! same_prefix: Wine named pipes · cross_prefix: host broker + capability grants.
//! Honesty: successful IPC ≠ ranked / vendor anti-cheat PASS.

pub mod broker;
pub mod smoke;

pub use broker::{BrokerConfig, BrokerHandle, Grant};
pub use smoke::run_interop_smoke;
