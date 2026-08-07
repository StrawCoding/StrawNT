//! strawnt-interopd — host broker daemon for cross-prefix IPC (NTW4).

use std::env;
use std::io::{BufRead, Write};
use std::net::TcpListener;
use std::process;
use std::thread;
use std::time::Duration;

use strawnt_interop::{BrokerConfig, BrokerHandle, Grant};

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let mut port: u16 = env::var("STRAWNT_INTEROP_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(strawnt_interop::broker::DEFAULT_PORT);
    let mut control_port: Option<u16> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--port" => {
                i += 1;
                port = args.get(i).and_then(|s| s.parse().ok()).unwrap_or_else(|| {
                    eprintln!("strawnt-interopd: bad --port");
                    process::exit(2);
                });
            }
            "--control-port" => {
                i += 1;
                control_port = Some(args.get(i).and_then(|s| s.parse().ok()).unwrap_or_else(|| {
                    eprintln!("strawnt-interopd: bad --control-port");
                    process::exit(2);
                }));
            }
            "--help" | "-h" => {
                println!(
                    "strawnt-interopd — StrawNT cross-prefix IPC broker (powered by Wine host)\n\
                     Usage: strawnt-interopd [--port N] [--control-port N]\n\
                     Loopback only. Default deny until GRANT via control port."
                );
                return;
            }
            other => {
                eprintln!("unknown arg: {other}");
                process::exit(2);
            }
        }
        i += 1;
    }

    let broker = match BrokerHandle::start(BrokerConfig {
        bind: "127.0.0.1".into(),
        port,
    }) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("strawnt-interopd: failed to bind: {e}");
            process::exit(1);
        }
    };
    println!(
        "strawnt-interopd listening on {} (powered by Wine host bridge)",
        broker.addr()
    );

    if let Some(cp) = control_port {
        let handle = broker.clone();
        thread::spawn(move || control_loop(cp, handle));
        println!("strawnt-interopd control on 127.0.0.1:{cp}");
    }

    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}

fn control_loop(port: u16, broker: BrokerHandle) {
    let listener = match TcpListener::bind(("127.0.0.1", port)) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("control bind failed: {e}");
            return;
        }
    };
    for stream in listener.incoming().flatten() {
        let broker = broker.clone();
        thread::spawn(move || {
            let mut stream = stream;
            let mut reader = std::io::BufReader::new(stream.try_clone().unwrap());
            let mut line = String::new();
            if reader.read_line(&mut line).is_err() {
                return;
            }
            let parts: Vec<&str> = line.trim().split_whitespace().collect();
            if parts.first() == Some(&"GRANT") && parts.len() >= 5 {
                let token = parts[1].to_string();
                let channel = parts[2].to_string();
                let prefixes: Vec<String> = parts[3..].iter().map(|s| (*s).to_string()).collect();
                let res = broker.grant(Grant {
                    token,
                    channel,
                    prefixes,
                });
                let msg = match res {
                    Ok(()) => "OK GRANT\n",
                    Err(_) => "ERR GRANT\n",
                };
                let _ = stream.write_all(msg.as_bytes());
            } else if parts.first() == Some(&"STATUS") {
                let n = broker.grants_snapshot().map(|g| g.len()).unwrap_or(0);
                let _ = write!(stream, "OK STATUS grants={n}\n");
            } else {
                let _ = stream.write_all(b"ERR unknown\n");
            }
        });
    }
}
