//! Host broker for cross-prefix Win32 IPC proxy (loopback TCP).

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::io::{BufRead, BufReader, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

pub const DEFAULT_PORT: u16 = 17864;
pub const MAX_PAYLOAD: usize = 4096;

#[derive(Debug, thiserror::Error)]
pub enum BrokerError {
    #[error("{0}")]
    Message(String),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, BrokerError>;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Grant {
    pub token: String,
    pub channel: String,
    pub prefixes: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct BrokerConfig {
    pub bind: String,
    pub port: u16,
}

impl Default for BrokerConfig {
    fn default() -> Self {
        let port = std::env::var("STRAWNT_INTEROP_PORT")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(DEFAULT_PORT);
        Self {
            bind: "127.0.0.1".into(),
            port,
        }
    }
}

#[derive(Debug, Default)]
struct ChannelState {
    queue: VecDeque<String>,
}

struct Inner {
    grants: HashMap<String, Grant>,
    channels: HashMap<String, ChannelState>,
}

impl Inner {
    fn new() -> Self {
        Self {
            grants: HashMap::new(),
            channels: HashMap::new(),
        }
    }

    fn insert_grant(&mut self, grant: Grant) -> Result<()> {
        if grant.token.is_empty() || grant.channel.is_empty() {
            return Err(BrokerError::Message("token and channel required".into()));
        }
        if grant.prefixes.len() < 2 {
            return Err(BrokerError::Message(
                "grant requires at least two prefixes".into(),
            ));
        }
        self.grants.insert(grant.token.clone(), grant);
        Ok(())
    }

    fn auth(&self, token: &str, prefix_id: &str, channel: &str) -> Result<()> {
        let g = self
            .grants
            .get(token)
            .ok_or_else(|| BrokerError::Message("deny: unknown token".into()))?;
        if g.channel != channel {
            return Err(BrokerError::Message("deny: channel mismatch".into()));
        }
        if !g.prefixes.iter().any(|p| p == prefix_id) {
            return Err(BrokerError::Message("deny: prefix not granted".into()));
        }
        Ok(())
    }

    fn send(&mut self, channel: &str, payload: String) -> Result<()> {
        if payload.len() > MAX_PAYLOAD {
            return Err(BrokerError::Message("payload too large".into()));
        }
        if payload.contains('\n') || payload.contains('\r') {
            return Err(BrokerError::Message("payload must be single-line".into()));
        }
        self.channels
            .entry(channel.to_string())
            .or_default()
            .queue
            .push_back(payload);
        Ok(())
    }

    fn try_recv(&mut self, channel: &str) -> Option<String> {
        self.channels
            .get_mut(channel)
            .and_then(|c| c.queue.pop_front())
    }
}

#[derive(Clone)]
pub struct BrokerHandle {
    inner: Arc<Mutex<Inner>>,
    stop: Arc<AtomicBool>,
    addr: SocketAddr,
    join: Arc<Mutex<Option<JoinHandle<()>>>>,
}

impl BrokerHandle {
    pub fn start(config: BrokerConfig) -> Result<Self> {
        let addr: SocketAddr = format!("{}:{}", config.bind, config.port)
            .parse()
            .map_err(|e| BrokerError::Message(format!("bad bind addr: {e}")))?;
        let listener = TcpListener::bind(addr)?;
        listener.set_nonblocking(true)?;
        let bound = listener.local_addr()?;
        let inner = Arc::new(Mutex::new(Inner::new()));
        let stop = Arc::new(AtomicBool::new(false));
        let inner_t = Arc::clone(&inner);
        let stop_t = Arc::clone(&stop);
        let join = thread::spawn(move || accept_loop(listener, inner_t, stop_t));
        Ok(Self {
            inner,
            stop,
            addr: bound,
            join: Arc::new(Mutex::new(Some(join))),
        })
    }

    pub fn addr(&self) -> SocketAddr {
        self.addr
    }

    pub fn port(&self) -> u16 {
        self.addr.port()
    }

    pub fn grant(&self, grant: Grant) -> Result<()> {
        self.inner
            .lock()
            .map_err(|_| BrokerError::Message("broker lock poisoned".into()))?
            .insert_grant(grant)
    }

    pub fn grants_snapshot(&self) -> Result<Vec<Grant>> {
        let g = self
            .inner
            .lock()
            .map_err(|_| BrokerError::Message("broker lock poisoned".into()))?;
        Ok(g.grants.values().cloned().collect())
    }

    pub fn stop(self) {
        self.stop.store(true, Ordering::SeqCst);
        // Nudge accept loop.
        let _ = TcpStream::connect(self.addr);
        if let Ok(mut guard) = self.join.lock() {
            if let Some(h) = guard.take() {
                let _ = h.join();
            }
        }
    }
}

fn accept_loop(listener: TcpListener, inner: Arc<Mutex<Inner>>, stop: Arc<AtomicBool>) {
    while !stop.load(Ordering::SeqCst) {
        match listener.accept() {
            Ok((stream, _)) => {
                if stop.load(Ordering::SeqCst) {
                    break;
                }
                let inner_c = Arc::clone(&inner);
                thread::spawn(move || {
                    let _ = handle_client(stream, inner_c);
                });
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(20));
            }
            Err(_) => {
                thread::sleep(Duration::from_millis(50));
            }
        }
    }
}

fn handle_client(stream: TcpStream, inner: Arc<Mutex<Inner>>) -> Result<()> {
    stream.set_read_timeout(Some(Duration::from_secs(30)))?;
    stream.set_write_timeout(Some(Duration::from_secs(30)))?;
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut writer = stream;
    let mut authed_channel: Option<String> = None;
    let mut line = String::new();

    loop {
        line.clear();
        let n = reader.read_line(&mut line)?;
        if n == 0 {
            break;
        }
        let cmd = line.trim_end_matches(['\r', '\n']);
        if cmd.is_empty() {
            continue;
        }
        let mut parts = cmd.splitn(5, ' ');
        let verb = parts.next().unwrap_or("");
        match verb {
            "AUTH" => {
                let token = parts.next().unwrap_or("");
                let prefix = parts.next().unwrap_or("");
                let _role = parts.next().unwrap_or("");
                let channel = parts.next().unwrap_or("");
                let res = {
                    let g = inner
                        .lock()
                        .map_err(|_| BrokerError::Message("lock".into()))?;
                    g.auth(token, prefix, channel)
                };
                match res {
                    Ok(()) => {
                        authed_channel = Some(channel.to_string());
                        write_line(&mut writer, "OK AUTH")?;
                    }
                    Err(e) => write_line(&mut writer, &format!("ERR {e}"))?,
                }
            }
            "SEND" => {
                let Some(ch) = authed_channel.clone() else {
                    write_line(&mut writer, "ERR not authenticated")?;
                    continue;
                };
                let payload = parts.next().unwrap_or("").to_string();
                // Rest of line after SEND may include spaces if we used splitn wrong —
                // re-parse: "SEND <payload>"
                let payload = cmd
                    .strip_prefix("SEND ")
                    .unwrap_or(payload.as_str())
                    .to_string();
                let res = {
                    let mut g = inner
                        .lock()
                        .map_err(|_| BrokerError::Message("lock".into()))?;
                    g.send(&ch, payload)
                };
                match res {
                    Ok(()) => write_line(&mut writer, "OK SEND")?,
                    Err(e) => write_line(&mut writer, &format!("ERR {e}"))?,
                }
            }
            "RECV" => {
                let Some(ch) = authed_channel.clone() else {
                    write_line(&mut writer, "ERR not authenticated")?;
                    continue;
                };
                let timeout_ms: u64 = parts.next().unwrap_or("5000").parse().unwrap_or(5000);
                let deadline = Instant::now() + Duration::from_millis(timeout_ms);
                let mut got = None;
                while Instant::now() < deadline {
                    {
                        let mut g = inner
                            .lock()
                            .map_err(|_| BrokerError::Message("lock".into()))?;
                        got = g.try_recv(&ch);
                    }
                    if got.is_some() {
                        break;
                    }
                    thread::sleep(Duration::from_millis(25));
                }
                match got {
                    Some(p) => write_line(&mut writer, &format!("DATA {p}"))?,
                    None => write_line(&mut writer, "ERR timeout")?,
                }
            }
            "QUIT" => {
                write_line(&mut writer, "OK QUIT")?;
                break;
            }
            _ => write_line(&mut writer, "ERR unknown verb")?,
        }
    }
    Ok(())
}

fn write_line(w: &mut TcpStream, line: &str) -> Result<()> {
    w.write_all(line.as_bytes())?;
    w.write_all(b"\n")?;
    w.flush()?;
    Ok(())
}

/// Blocking client helper for host-side tests (not Wine PE).
pub fn client_exchange(
    addr: SocketAddr,
    token: &str,
    prefix_id: &str,
    role: &str,
    channel: &str,
    send: Option<&str>,
    recv_timeout_ms: u64,
) -> Result<Option<String>> {
    let mut stream = TcpStream::connect(addr)?;
    stream.set_read_timeout(Some(Duration::from_secs(60)))?;
    stream.set_write_timeout(Some(Duration::from_secs(60)))?;
    let mut reader = BufReader::new(stream.try_clone()?);

    write_line(
        &mut stream,
        &format!("AUTH {token} {prefix_id} {role} {channel}"),
    )?;
    expect_ok(&mut reader, "OK AUTH")?;

    if let Some(payload) = send {
        write_line(&mut stream, &format!("SEND {payload}"))?;
        expect_ok(&mut reader, "OK SEND")?;
    }

    let mut received = None;
    if recv_timeout_ms > 0 {
        write_line(&mut stream, &format!("RECV {recv_timeout_ms}"))?;
        let mut line = String::new();
        reader.read_line(&mut line)?;
        let line = line.trim_end_matches(['\r', '\n']);
        if let Some(p) = line.strip_prefix("DATA ") {
            received = Some(p.to_string());
        } else if line.starts_with("ERR ") {
            return Err(BrokerError::Message(line.to_string()));
        } else {
            return Err(BrokerError::Message(format!("unexpected: {line}")));
        }
    }

    write_line(&mut stream, "QUIT")?;
    let _ = expect_ok(&mut reader, "OK QUIT");
    Ok(received)
}

fn expect_ok(reader: &mut BufReader<TcpStream>, want: &str) -> Result<()> {
    let mut line = String::new();
    reader.read_line(&mut line)?;
    let line = line.trim_end_matches(['\r', '\n']);
    if line == want {
        Ok(())
    } else {
        Err(BrokerError::Message(format!("expected {want}, got {line}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deny_without_grant() {
        let broker = BrokerHandle::start(BrokerConfig {
            bind: "127.0.0.1".into(),
            port: 0,
        })
        .unwrap();
        let addr = broker.addr();
        let err = client_exchange(addr, "nope", "a", "ac", "ch", Some("x"), 0).unwrap_err();
        assert!(err.to_string().contains("deny") || err.to_string().contains("ERR"));
        broker.stop();
    }

    #[test]
    fn cross_session_message() {
        let broker = BrokerHandle::start(BrokerConfig {
            bind: "127.0.0.1".into(),
            port: 0,
        })
        .unwrap();
        broker
            .grant(Grant {
                token: "tok".into(),
                channel: "demo".into(),
                prefixes: vec!["pfx-a".into(), "pfx-b".into()],
            })
            .unwrap();
        let addr = broker.addr();

        let send_h = thread::spawn(move || {
            client_exchange(addr, "tok", "pfx-a", "game", "demo", Some("HELLO"), 0)
        });
        thread::sleep(Duration::from_millis(50));
        let got = client_exchange(addr, "tok", "pfx-b", "ac", "demo", None, 3000).unwrap();
        assert_eq!(got.as_deref(), Some("HELLO"));
        send_h.join().unwrap().unwrap();
        broker.stop();
    }

    #[test]
    fn prefix_not_in_grant_denied() {
        let broker = BrokerHandle::start(BrokerConfig {
            bind: "127.0.0.1".into(),
            port: 0,
        })
        .unwrap();
        broker
            .grant(Grant {
                token: "tok".into(),
                channel: "demo".into(),
                prefixes: vec!["pfx-a".into(), "pfx-b".into()],
            })
            .unwrap();
        let err = client_exchange(broker.addr(), "tok", "evil", "ac", "demo", Some("x"), 0)
            .unwrap_err();
        assert!(err.to_string().contains("deny") || err.to_string().contains("ERR"));
        broker.stop();
    }
}
