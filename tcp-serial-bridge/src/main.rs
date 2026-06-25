use std::fs::OpenOptions;
use std::io::{self, ErrorKind, Read, Write};
use std::net::TcpListener;
use std::thread;
use std::time::Duration;

use serde::Deserialize;
use serialport::SerialPort;

#[derive(Deserialize)]
struct Config {
    bridge: Vec<BridgeEntry>,
}

#[derive(Deserialize, Clone)]
struct BridgeEntry {
    device: String,
    port: u16,
    baud: Option<u32>,
}

// Unified serial handle: UART (via serialport crate) or raw file (for RPMSG).
// Raw file is used when no baud is configured — ttyRPMSG0 ignores termios settings
// and serialport's tcgetattr may fail on it.
enum Serial {
    Uart(Box<dyn SerialPort>),
    Raw(std::fs::File),
}

impl Read for Serial {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        match self {
            Serial::Uart(p) => p.read(buf),
            Serial::Raw(f) => f.read(buf),
        }
    }
}

impl Write for Serial {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        match self {
            Serial::Uart(p) => p.write(buf),
            Serial::Raw(f) => f.write(buf),
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        match self {
            Serial::Uart(p) => p.flush(),
            Serial::Raw(f) => f.flush(),
        }
    }
}

// Box<dyn SerialPort> is Send on Linux (TTYPort is Send).
// File is Send. Both arms are Send so the enum is Send.
unsafe impl Send for Serial {}

fn open_serial(entry: &BridgeEntry) -> io::Result<(Serial, Serial)> {
    if let Some(baud) = entry.baud {
        let port = serialport::new(&entry.device, baud)
            .timeout(Duration::from_millis(100))
            .open()
            .map_err(|e| io::Error::new(ErrorKind::Other, e))?;
        let clone = port
            .try_clone()
            .map_err(|e| io::Error::new(ErrorKind::Other, e))?;
        Ok((Serial::Uart(port), Serial::Uart(clone)))
    } else {
        let f = OpenOptions::new().read(true).write(true).open(&entry.device)?;
        let clone = f.try_clone()?;
        Ok((Serial::Raw(f), Serial::Raw(clone)))
    }
}

// Copy bytes from `from` to `to` until either side errors or closes.
// UART read timeouts are not treated as errors — they just mean no data yet.
fn relay(mut from: impl Read, mut to: impl Write) {
    let mut buf = [0u8; 4096];
    loop {
        match from.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                if to.write_all(&buf[..n]).is_err() {
                    break;
                }
            }
            Err(ref e) if matches!(e.kind(), ErrorKind::TimedOut | ErrorKind::WouldBlock) => {}
            Err(_) => break,
        }
    }
}

fn run(entry: BridgeEntry) {
    let listener = TcpListener::bind(format!("0.0.0.0:{}", entry.port))
        .unwrap_or_else(|e| panic!("{}:{} bind: {}", entry.device, entry.port, e));
    eprintln!("[{}] listening on :{}", entry.device, entry.port);

    loop {
        // Open serial device, retrying until it succeeds (handles USB re-enumeration,
        // and the window between boot and DSP firmware load for ttyRPMSG0).
        let (rx, tx) = loop {
            match open_serial(&entry) {
                Ok(pair) => break pair,
                Err(e) => {
                    eprintln!("[{}] open failed: {}, retrying in 2s", entry.device, e);
                    thread::sleep(Duration::from_secs(2));
                }
            }
        };

        eprintln!("[{}] waiting for connection", entry.device);
        let (stream, peer) = match listener.accept() {
            Ok(p) => p,
            Err(e) => {
                eprintln!("[{}] accept: {}", entry.device, e);
                continue;
            }
        };
        eprintln!("[{}] <- {}", entry.device, peer);
        let _ = stream.set_nodelay(true);

        let stream_tx = match stream.try_clone() {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[{}] stream clone: {}", entry.device, e);
                continue;
            }
        };

        // Two threads: one per direction. When either side drops the connection,
        // both threads eventually exit (the other will error on its next write/read),
        // then the outer loop reopens the serial device for the next client.
        let t1 = thread::spawn(move || relay(rx, stream_tx));
        let t2 = thread::spawn(move || relay(stream, tx));
        let _ = t1.join();
        let _ = t2.join();
        eprintln!("[{}] disconnected", entry.device);
    }
}

fn main() {
    let src = std::fs::read_to_string("/etc/tcp-serial-bridge.conf")
        .expect("cannot read /etc/tcp-serial-bridge.conf");
    let config: Config = toml::from_str(&src).expect("config parse error");

    let threads: Vec<_> = config
        .bridge
        .into_iter()
        .map(|e| thread::spawn(move || run(e)))
        .collect();

    for t in threads {
        let _ = t.join();
    }
}
