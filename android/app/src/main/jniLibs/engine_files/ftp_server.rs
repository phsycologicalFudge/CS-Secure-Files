use get_if_addrs::get_if_addrs;
use once_cell::sync::Lazy;
use std::ffi::CStr;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpListener, TcpStream, UdpSocket};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

static FTP_STATE: Lazy<Mutex<Option<FtpHandle>>> = Lazy::new(|| Mutex::new(None));

struct FtpHandle {
    shutdown: Arc<AtomicBool>,
    thread: Option<thread::JoinHandle<()>>,
}

fn cstring(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    let s = unsafe { CStr::from_ptr(ptr) };
    s.to_string_lossy().into_owned()
}

fn send_line(stream: &mut TcpStream, line: &str) {
    let _ = stream.write_all(line.as_bytes());
    let _ = stream.write_all(b"\r\n");
    let _ = stream.flush();
}

fn pick_lan_ip() -> Ipv4Addr {
    for iface in get_if_addrs().unwrap_or_default() {
        if let IpAddr::V4(ip) = iface.ip() {
            let o = ip.octets();
            let private = o[0] == 10
                || (o[0] == 172 && (16..=31).contains(&o[1]))
                || (o[0] == 192 && o[1] == 168);
            if private && !iface.is_loopback() {
                return ip;
            }
        }
    }
    Ipv4Addr::new(127, 0, 0, 1)
}

fn select_pasv_ip(control: &TcpStream) -> Ipv4Addr {
    if let Ok(SocketAddr::V4(local)) = control.local_addr() {
        let ip = *local.ip();
        if ip != Ipv4Addr::UNSPECIFIED && !ip.is_loopback() {
            return ip;
        }
    }
    if let Ok(SocketAddr::V4(peer)) = control.peer_addr() {
        if let Ok(udp) = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)) {
            let _ = udp.connect((*peer.ip(), peer.port()));
            if let Ok(SocketAddr::V4(local)) = udp.local_addr() {
                let ip = *local.ip();
                if ip != Ipv4Addr::UNSPECIFIED && !ip.is_loopback() {
                    return ip;
                }
            }
        }
    }
    pick_lan_ip()
}

fn sanitize_existing(root: &Path, cwd: &Path, arg: &str) -> Option<PathBuf> {
    let trimmed = arg.trim();
    let mut base = if trimmed.is_empty() || trimmed.starts_with('/') {
        root.to_path_buf()
    } else {
        cwd.to_path_buf()
    };
    if !trimmed.is_empty() {
        if trimmed.contains("..") {
            return None;
        }
        base.push(trimmed.trim_start_matches('/'));
    }
    let canonical = std::fs::canonicalize(&base).ok()?;
    let root_real = std::fs::canonicalize(root).ok()?;
    if !canonical.starts_with(&root_real) {
        return None;
    }
    Some(canonical)
}

fn sanitize_new_target(root: &Path, cwd: &Path, arg: &str) -> Option<PathBuf> {
    let trimmed = arg.trim();
    if trimmed.is_empty() || trimmed.ends_with('/') || trimmed.contains("..") {
        return None;
    }
    let mut parent = if trimmed.starts_with('/') {
        root.to_path_buf()
    } else {
        cwd.to_path_buf()
    };
    let name = trimmed.trim_start_matches('/');

    let (dir_part, file_part) = match name.rsplit_once('/') {
        Some((d, f)) => (d, f),
        None => ("", name),
    };
    if !dir_part.is_empty() {
        parent.push(dir_part);
    }
    let parent_real = std::fs::canonicalize(&parent).ok()?;
    let root_real = std::fs::canonicalize(root).ok()?;
    if !parent_real.starts_with(&root_real) {
        return None;
    }
    let mut final_path = parent_real;
    final_path.push(file_part);
    Some(final_path)
}

fn format_dir_entry(path: &Path) -> String {
    let metadata = match std::fs::metadata(path) {
        Ok(m) => m,
        Err(_) => return String::new(),
    };
    let is_dir = metadata.is_dir();
    let size = metadata.len();
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let kind = if is_dir { 'd' } else { '-' };
    format!("{kind}rw-rw-rw- 1 owner group {size:>10} Jan 01 00:00 {name}")
}

fn handle_list(_root: &Path, cwd: &Path, mut data_stream: TcpStream) {
    let entries = match std::fs::read_dir(cwd) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let line = format_dir_entry(&path);
        if !line.is_empty() {
            let _ = data_stream.write_all(line.as_bytes());
            let _ = data_stream.write_all(b"\r\n");
        }
    }
    let _ = data_stream.flush();
}

fn handle_retr(path: &Path, mut data_stream: TcpStream) {
    let mut file = match std::fs::File::open(path) {
        Ok(f) => f,
        Err(_) => return,
    };
    let mut buf = [0u8; 8192];
    loop {
        match file.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                let _ = data_stream.write_all(&buf[..n]);
            }
            Err(_) => break,
        }
    }
    let _ = data_stream.flush();
}

fn handle_stor(path: &Path, mut data_stream: TcpStream) {
    if let Some(p) = path.parent() {
        let _ = std::fs::create_dir_all(p);
    }
    let mut file = match std::fs::File::create(path) {
        Ok(f) => f,
        Err(_) => return,
    };
    let mut buf = [0u8; 8192];
    loop {
        match data_stream.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                let _ = file.write_all(&buf[..n]);
            }
            Err(_) => break,
        }
    }
    let _ = file.flush();
}

fn handle_client(
    mut stream: TcpStream,
    root: PathBuf,
    expected_user: String,
    expected_pass: String,
    shutdown: Arc<AtomicBool>,
) {
    let mut logged_in = false;
    let mut last_user = String::new();
    let mut cwd = root.clone();
    let mut pasv_listener: Option<TcpListener> = None;

    send_line(&mut stream, "220 ColourSwift FTP Ready");

    let mut reader = BufReader::new(stream.try_clone().unwrap());

    loop {
        if shutdown.load(Ordering::SeqCst) {
            break;
        }

        let mut line = String::new();
        let n = match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(n) => n,
            Err(_) => break,
        };
        if n == 0 {
            break;
        }
        let trimmed = line
            .trim_end_matches(|c| c == '\r' || c == '\n')
            .to_string();
        if trimmed.is_empty() {
            continue;
        }
        let mut parts = trimmed.splitn(2, ' ');
        let cmd = parts.next().unwrap_or("").to_uppercase();
        let arg = parts.next().unwrap_or("").trim().to_string();

        match cmd.as_str() {
            "USER" => {
                last_user = arg.clone();
                send_line(&mut stream, "331 User name okay, need password");
            }
            "PASS" => {
                if last_user == expected_user && arg == expected_pass {
                    logged_in = true;
                    send_line(&mut stream, "230 User logged in");
                } else {
                    send_line(&mut stream, "530 Authentication failed");
                }
            }
            "SYST" => {
                send_line(&mut stream, "215 UNIX Type: L8");
            }
            "TYPE" => {
                send_line(&mut stream, "200 Type set");
            }
            "NOOP" => {
                send_line(&mut stream, "200 OK");
            }
            "FEAT" => {
                send_line(&mut stream, "211-Features");
                send_line(&mut stream, " UTF8");
                send_line(&mut stream, " EPSV");
                send_line(&mut stream, " PASV");
                send_line(&mut stream, "211 End");
            }
            "OPTS" => {
                if arg.to_uppercase().starts_with("UTF8") {
                    send_line(&mut stream, "200 UTF8 set to on");
                } else {
                    send_line(&mut stream, "501 Option not supported");
                }
            }
            "AUTH" => {
                send_line(&mut stream, "502 TLS not supported");
            }
            "PWD" => {
                let root_real = std::fs::canonicalize(&root).unwrap_or(root.clone());
                let cwd_real = std::fs::canonicalize(&cwd).unwrap_or(cwd.clone());
                let rel = cwd_real.strip_prefix(&root_real).unwrap_or(&cwd_real);
                let mut path_str = String::from("/");
                path_str.push_str(&rel.to_string_lossy());
                let display = if path_str == "/" || path_str.starts_with("//") {
                    "/".to_string()
                } else {
                    path_str
                };
                send_line(
                    &mut stream,
                    &format!("257 \"{}\" is the current directory", display),
                );
            }
            "CDUP" => {
                if !logged_in {
                    send_line(&mut stream, "530 Not logged in");
                    continue;
                }
                let root_real = std::fs::canonicalize(&root).unwrap_or(root.clone());
                let cwd_real = std::fs::canonicalize(&cwd).unwrap_or(cwd.clone());
                if let Some(parent) = cwd_real.parent() {
                    if parent.starts_with(&root_real) {
                        cwd = parent.to_path_buf();
                        send_line(&mut stream, "200 Command okay");
                    } else {
                        send_line(&mut stream, "550 Not permitted");
                    }
                } else {
                    send_line(&mut stream, "550 Not permitted");
                }
            }
            "CWD" => {
                if !logged_in {
                    send_line(&mut stream, "530 Not logged in");
                    continue;
                }
                if arg == ".." || arg.ends_with("/..") {
                    let root_real = std::fs::canonicalize(&root).unwrap_or(root.clone());
                    let cwd_real = std::fs::canonicalize(&cwd).unwrap_or(cwd.clone());
                    if let Some(parent) = cwd_real.parent() {
                        if parent.starts_with(&root_real) {
                            cwd = parent.to_path_buf();
                            send_line(&mut stream, "250 Directory changed");
                        } else {
                            send_line(&mut stream, "550 Failed to change directory");
                        }
                    } else {
                        send_line(&mut stream, "550 Failed to change directory");
                    }
                } else {
                    match sanitize_existing(&root, &cwd, &arg) {
                        Some(p) if p.is_dir() => {
                            cwd = p;
                            send_line(&mut stream, "250 Directory changed");
                        }
                        _ => {
                            send_line(&mut stream, "550 Failed to change directory");
                        }
                    }
                }
            }
            "EPSV" => {
                if !logged_in {
                    send_line(&mut stream, "530 Not logged in");
                    continue;
                }
                let listener = TcpListener::bind(("0.0.0.0", 0)).unwrap();
                let port = listener.local_addr().unwrap().port();
                pasv_listener = Some(listener);
                send_line(
                    &mut stream,
                    &format!("229 Entering Extended Passive Mode (|||{}|)", port),
                );
            }
            "PASV" => {
                if !logged_in {
                    send_line(&mut stream, "530 Not logged in");
                    continue;
                }
                let listener = match TcpListener::bind(("0.0.0.0", 0)) {
                    Ok(l) => l,
                    Err(_) => {
                        send_line(&mut stream, "425 Cannot open passive connection");
                        continue;
                    }
                };
                let local = match listener.local_addr() {
                    Ok(a) => a,
                    Err(_) => {
                        send_line(&mut stream, "425 Cannot get passive address");
                        continue;
                    }
                };
                let port = local.port();
                let ip = select_pasv_ip(&stream);
                let h = ip.octets();
                let p1 = port / 256;
                let p2 = port % 256;
                pasv_listener = Some(listener);
                let resp = format!(
                    "227 Entering Passive Mode ({},{},{},{},{},{})",
                    h[0], h[1], h[2], h[3], p1, p2
                );
                send_line(&mut stream, &resp);
            }
            "LIST" => {
                if !logged_in {
                    send_line(&mut stream, "530 Not logged in");
                    continue;
                }
                let listener = match pasv_listener.take() {
                    Some(l) => l,
                    None => {
                        send_line(&mut stream, "425 Use PASV first");
                        continue;
                    }
                };
                send_line(&mut stream, "150 Opening data connection for LIST");
                match listener.accept() {
                    Ok((mut data_stream, _)) => {
                        handle_list(&root, &cwd, data_stream.try_clone().unwrap());
                        let _ = data_stream.shutdown(std::net::Shutdown::Both);
                        send_line(&mut stream, "226 Transfer complete");
                    }
                    Err(_) => {
                        send_line(&mut stream, "425 Cannot open data connection");
                    }
                }
            }
            "RETR" => {
                if !logged_in {
                    send_line(&mut stream, "530 Not logged in");
                    continue;
                }
                let listener = match pasv_listener.take() {
                    Some(l) => l,
                    None => {
                        send_line(&mut stream, "425 Use PASV first");
                        continue;
                    }
                };
                let target = match sanitize_existing(&root, &cwd, &arg) {
                    Some(p) if p.is_file() => p,
                    _ => {
                        send_line(&mut stream, "550 File unavailable");
                        continue;
                    }
                };
                send_line(&mut stream, "150 Opening data connection for RETR");
                match listener.accept() {
                    Ok((mut data_stream, _)) => {
                        handle_retr(&target, data_stream.try_clone().unwrap());
                        let _ = data_stream.shutdown(std::net::Shutdown::Both);
                        send_line(&mut stream, "226 Transfer complete");
                    }
                    Err(_) => {
                        send_line(&mut stream, "425 Cannot open data connection");
                    }
                }
            }
            "STOR" => {
                if !logged_in {
                    send_line(&mut stream, "530 Not logged in");
                    continue;
                }
                let listener = match pasv_listener.take() {
                    Some(l) => l,
                    None => {
                        send_line(&mut stream, "425 Use PASV first");
                        continue;
                    }
                };
                let target = match sanitize_new_target(&root, &cwd, &arg) {
                    Some(p) => p,
                    None => {
                        send_line(&mut stream, "550 Invalid path");
                        continue;
                    }
                };
                send_line(&mut stream, "150 Opening data connection for STOR");
                match listener.accept() {
                    Ok((mut data_stream, _)) => {
                        handle_stor(&target, data_stream.try_clone().unwrap());
                        let _ = data_stream.shutdown(std::net::Shutdown::Both);
                        send_line(&mut stream, "226 Transfer complete");
                    }
                    Err(_) => {
                        send_line(&mut stream, "425 Cannot open data connection");
                    }
                }
            }
            "QUIT" => {
                send_line(&mut stream, "221 Goodbye");
                break;
            }
            _ => {
                send_line(&mut stream, "502 Command not implemented");
            }
        }
    }
}

fn ftp_server_main(
    addr: SocketAddr,
    root: PathBuf,
    user: String,
    pass: String,
    shutdown: Arc<AtomicBool>,
) {
    let listener = match TcpListener::bind(addr) {
        Ok(l) => l,
        Err(_) => return,
    };
    let _ = std::fs::create_dir_all(&root);
    listener.set_nonblocking(true).ok();
    while !shutdown.load(Ordering::SeqCst) {
        match listener.accept() {
            Ok((stream, _)) => {
                let root_clone = root.clone();
                let user_clone = user.clone();
                let pass_clone = pass.clone();
                let shutdown_clone = shutdown.clone();
                thread::spawn(move || {
                    handle_client(stream, root_clone, user_clone, pass_clone, shutdown_clone);
                });
            }
            Err(e) => {
                if e.kind() == std::io::ErrorKind::WouldBlock {
                    std::thread::sleep(std::time::Duration::from_millis(100));
                    continue;
                } else {
                    break;
                }
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn ftp_start_with_root(
    port: i32,
    root: *const c_char,
    user: *const c_char,
    pass: *const c_char,
) {
    let root_path = PathBuf::from(cstring(root));
    let _ = std::fs::create_dir_all(&root_path);

    let username = cstring(user);
    let password = cstring(pass);

    let mut lock = FTP_STATE.lock().unwrap();
    if lock.is_some() {
        return;
    }

    let shutdown_flag = Arc::new(AtomicBool::new(false));
    let shutdown_clone = shutdown_flag.clone();

    let addr = SocketAddr::from(([0, 0, 0, 0], port as u16));

    let handle = thread::spawn(move || {
        ftp_server_main(addr, root_path, username, password, shutdown_clone);
    });

    *lock = Some(FtpHandle {
        shutdown: shutdown_flag,
        thread: Some(handle),
    });
}

#[no_mangle]
pub extern "C" fn ftp_start(port: i32, user: *const c_char, pass: *const c_char) {
    let dot = std::ffi::CString::new(".").unwrap();
    ftp_start_with_root(port, dot.as_ptr(), user, pass);
}

#[no_mangle]
pub extern "C" fn ftp_stop() {
    let mut lock = FTP_STATE.lock().unwrap();
    if let Some(handle) = lock.as_mut() {
        handle.shutdown.store(true, Ordering::SeqCst);
        if let Some(join) = handle.thread.take() {
            let _ = join.join();
        }
    }
    *lock = None;
}

#[no_mangle]
pub extern "C" fn ftp_status() -> i32 {
    let lock = FTP_STATE.lock().unwrap();
    if lock.is_some() {
        1
    } else {
        0
    }
}
