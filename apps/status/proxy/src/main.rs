//! Gatus の statuses API だけを中継し、CORS ヘッダを付ける最小のサーバー。
//! std のみ・unsafe なし。受け付けるのは GET/HEAD /api/v1/endpoints/statuses だけ。
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

const PATH: &str = "/api/v1/endpoints/statuses";
const MAX_HEAD: usize = 8 * 1024;
const MAX_BODY: u64 = 4 * 1024 * 1024;
const MAX_CONNS: usize = 64;
const TIMEOUT: Duration = Duration::from_secs(5);

fn env(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

fn main() {
    let listen = env("LISTEN", "0.0.0.0:8081");
    let upstream = env("UPSTREAM", "127.0.0.1:8080");
    let origin = env("ALLOW_ORIGIN", "https://status.riya.work");
    let active = Arc::new(AtomicUsize::new(0));
    let listener = TcpListener::bind(&listen).unwrap_or_else(|e| panic!("bind {listen}: {e}"));
    for conn in listener.incoming().flatten() {
        // 同時接続の上限。超えたら黙って切る
        if active.fetch_add(1, Ordering::SeqCst) >= MAX_CONNS {
            active.fetch_sub(1, Ordering::SeqCst);
            continue;
        }
        let (upstream, origin, active) = (upstream.clone(), origin.clone(), active.clone());
        thread::spawn(move || {
            let _ = handle(conn, &upstream, &origin);
            active.fetch_sub(1, Ordering::SeqCst);
        });
    }
}

fn reply(mut c: impl Write, status: &str) -> std::io::Result<()> {
    write!(c, "HTTP/1.1 {status}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
}

/// リクエスト行から「許可する中継先 (パス + クエリ)」を取り出す。許可しなければ Err(返すステータス)
fn route(head: &str) -> Result<(bool, String), &'static str> {
    let line = head.lines().next().ok_or("400 Bad Request")?;
    let mut p = line.split(' ');
    let (method, target, version) = (p.next(), p.next(), p.next());
    if !matches!(version, Some("HTTP/1.1" | "HTTP/1.0")) || p.next().is_some() {
        return Err("400 Bad Request");
    }
    let is_head = match method {
        Some("GET") => false,
        Some("HEAD") => true,
        _ => return Err("405 Method Not Allowed"),
    };
    let target = target.ok_or("400 Bad Request")?;
    let (path, query) = target.split_once('?').unwrap_or((target, ""));
    if path != PATH {
        return Err("404 Not Found");
    }
    // クエリは pageSize=60 のような英数字だけ通す (上流へ余計な文字を流さない)
    if !query.bytes().all(|b| b.is_ascii_alphanumeric() || b"=&_.-".contains(&b)) {
        return Err("400 Bad Request");
    }
    let q = if query.is_empty() { String::new() } else { format!("?{query}") };
    Ok((is_head, format!("{PATH}{q}")))
}

fn read_head(c: &mut TcpStream) -> Option<String> {
    let mut buf = Vec::new();
    let mut b = [0u8; 1024];
    while !buf.windows(4).any(|w| w == b"\r\n\r\n") {
        if buf.len() > MAX_HEAD {
            return None;
        }
        match c.read(&mut b) {
            Ok(0) | Err(_) => return None,
            Ok(n) => buf.extend_from_slice(&b[..n]),
        }
    }
    String::from_utf8(buf).ok()
}

fn handle(mut c: TcpStream, upstream: &str, origin: &str) -> std::io::Result<()> {
    c.set_read_timeout(Some(TIMEOUT))?;
    c.set_write_timeout(Some(TIMEOUT))?;
    let Some(head) = read_head(&mut c) else { return reply(c, "400 Bad Request") };
    let (is_head, target) = match route(&head) {
        Ok(r) => r,
        Err(status) => return reply(c, status),
    };

    let addr = upstream.to_socket_addrs()?.next().ok_or(std::io::ErrorKind::NotFound)?;
    let Ok(mut u) = TcpStream::connect_timeout(&addr, TIMEOUT) else { return reply(c, "502 Bad Gateway") };
    u.set_read_timeout(Some(TIMEOUT))?;
    u.set_write_timeout(Some(TIMEOUT))?;
    let method = if is_head { "HEAD" } else { "GET" };
    // 圧縮なし・接続は使い捨てにして、応答をそのまま EOF まで中継できるようにする
    u.write_all(format!("{method} {target} HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n").as_bytes())?;
    let mut resp = Vec::new();
    if u.take(MAX_BODY).read_to_end(&mut resp).is_err() {
        return reply(c, "502 Bad Gateway");
    }
    let Some(i) = resp.windows(2).position(|w| w == b"\r\n") else { return reply(c, "502 Bad Gateway") };
    // ステータス行の直後に CORS ヘッダを差し込む
    c.write_all(&resp[..i + 2])?;
    write!(c, "Access-Control-Allow-Origin: {origin}\r\n")?;
    c.write_all(&resp[i + 2..])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn route_allows_only_statuses() {
        let ok = route("GET /api/v1/endpoints/statuses?pageSize=60 HTTP/1.1\r\n\r\n").unwrap();
        assert_eq!(ok, (false, format!("{PATH}?pageSize=60")));
        assert!(route("HEAD /api/v1/endpoints/statuses HTTP/1.1\r\n\r\n").unwrap().0);
        assert_eq!(route("GET /api/v1/config HTTP/1.1\r\n\r\n"), Err("404 Not Found"));
        assert_eq!(route("GET /api/v1/endpoints/statuses/x HTTP/1.1\r\n\r\n"), Err("404 Not Found"));
        assert_eq!(route("POST /api/v1/endpoints/statuses HTTP/1.1\r\n\r\n"), Err("405 Method Not Allowed"));
        assert_eq!(route("GET /api/v1/endpoints/statuses?a=%0d HTTP/1.1\r\n\r\n"), Err("400 Bad Request"));
        assert_eq!(route("GET /api/v1/endpoints/statuses HTTP/2\r\n\r\n"), Err("400 Bad Request"));
        assert_eq!(route("garbage"), Err("400 Bad Request"));
    }

    fn request(addr: std::net::SocketAddr, req: &str) -> String {
        let mut s = TcpStream::connect(addr).unwrap();
        s.write_all(req.as_bytes()).unwrap();
        let mut out = String::new();
        s.read_to_string(&mut out).unwrap();
        out
    }

    #[test]
    fn proxies_with_cors_header() {
        let up = TcpListener::bind("127.0.0.1:0").unwrap();
        let up_addr = up.local_addr().unwrap().to_string();
        thread::spawn(move || {
            let (mut s, _) = up.accept().unwrap();
            let got = read_head(&mut s).unwrap();
            // 中継先には絞ったリクエストだけが届く
            assert!(got.starts_with("GET /api/v1/endpoints/statuses?pageSize=60 HTTP/1.1\r\nHost: localhost"), "{got}");
            s.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n[]").unwrap();
        });
        let front = TcpListener::bind("127.0.0.1:0").unwrap();
        let front_addr = front.local_addr().unwrap();
        thread::spawn(move || {
            let (c, _) = front.accept().unwrap();
            handle(c, &up_addr, "https://example.test").unwrap();
        });
        let out = request(front_addr, "GET /api/v1/endpoints/statuses?pageSize=60 HTTP/1.1\r\nHost: x\r\n\r\n");
        assert!(out.starts_with("HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: https://example.test\r\n"), "{out}");
        assert!(out.ends_with("\r\n\r\n[]"));
    }

    #[test]
    fn upstream_down_is_502() {
        let front = TcpListener::bind("127.0.0.1:0").unwrap();
        let front_addr = front.local_addr().unwrap();
        thread::spawn(move || {
            let (c, _) = front.accept().unwrap();
            handle(c, "127.0.0.1:1", "x").unwrap();
        });
        assert!(request(front_addr, "GET /api/v1/endpoints/statuses HTTP/1.1\r\n\r\n").starts_with("HTTP/1.1 502"));
    }
}
