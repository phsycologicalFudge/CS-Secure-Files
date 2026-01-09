use once_cell::sync::Lazy;
use std::ffi::CStr;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

static HTTP_STATE: Lazy<Mutex<Option<HttpHandle>>> = Lazy::new(|| Mutex::new(None));

struct HttpHandle {
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

fn write_response(
    stream: &mut TcpStream,
    status_code: u16,
    status_text: &str,
    headers: &[(&str, String)],
    body: Option<&[u8]>,
) {
    let mut header_block = format!("HTTP/1.1 {} {}\r\n", status_code, status_text);
    let mut has_length = false;
    for (k, v) in headers {
        if k.eq_ignore_ascii_case("content-length") {
            has_length = true;
        }
        header_block.push_str(k);
        header_block.push_str(": ");
        header_block.push_str(v);
        header_block.push_str("\r\n");
    }
    let body_len = body.map(|b| b.len()).unwrap_or(0);
    if !has_length {
        header_block.push_str(&format!("Content-Length: {}\r\n", body_len));
    }
    header_block.push_str("\r\n");
    let _ = stream.write_all(header_block.as_bytes());
    if let Some(b) = body {
        let _ = stream.write_all(b);
    }
    let _ = stream.flush();
}

fn sanitize_path(root: &Path, arg: &str) -> Option<PathBuf> {
    let trimmed = arg.trim();
    if trimmed.is_empty() || trimmed == "/" {
        return Some(root.to_path_buf());
    }
    if trimmed.contains("..") {
        return None;
    }

    let mut base = root.to_path_buf();
    let rel = trimmed.trim_start_matches('/');
    base.push(rel);

    if !base.starts_with(root) {
        return None;
    }
    Some(base)
}

fn hex_val(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}

fn url_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'%' if i + 2 < bytes.len() => {
                if let (Some(h), Some(l)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2])) {
                    out.push((h << 4) | l);
                    i += 3;
                } else {
                    out.push(bytes[i]);
                    i += 1;
                }
            }
            b'+' => {
                out.push(b' ');
                i += 1;
            }
            b => {
                out.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn parse_query_param(path: &str, key: &str) -> Option<String> {
    let mut parts = path.splitn(2, '?');
    let _ = parts.next()?;
    let query = parts.next()?;
    for pair in query.split('&') {
        let mut kv = pair.splitn(2, '=');
        let k = kv.next().unwrap_or("");
        let v = kv.next().unwrap_or("");
        if k == key {
            return Some(url_decode(v));
        }
    }
    None
}

fn split_path_and_query(path: &str) -> (String, Option<String>) {
    let mut parts = path.splitn(2, '?');
    let p = parts.next().unwrap_or("").to_string();
    let q = parts.next().map(|s| s.to_string());
    (p, q)
}

fn extract_header(headers: &[(String, String)], name: &str) -> Option<String> {
    for (k, v) in headers {
        if k.eq_ignore_ascii_case(name) {
            return Some(v.trim().to_string());
        }
    }
    None
}

fn handle_list(root: &Path, dir_path: &Path, stream: &mut TcpStream) {
    let entries = match std::fs::read_dir(dir_path) {
        Ok(e) => e,
        Err(_) => {
            let body = b"{\"error\":\"cannot read directory\"}";
            write_response(
                stream,
                500,
                "Internal Server Error",
                &[("Content-Type", "application/json".to_string())],
                Some(body),
            );
            return;
        }
    };
    let mut items = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        let metadata = match std::fs::metadata(&path) {
            Ok(m) => m,
            Err(_) => continue,
        };
        let name = match path.file_name() {
            Some(n) => n.to_string_lossy().into_owned(),
            None => continue,
        };
        let is_dir = metadata.is_dir();
        let size = metadata.len();
        let item = format!(
            "{{\"name\":\"{}\",\"is_dir\":{},\"size\":{}}}",
            name.replace('"', "\\\""),
            if is_dir { "true" } else { "false" },
            size
        );
        items.push(item);
    }
    let json = format!("[{}]", items.join(","));
    write_response(
        stream,
        200,
        "OK",
        &[("Content-Type", "application/json".to_string())],
        Some(json.as_bytes()),
    );
}

fn handle_download(root: &Path, file_path: &Path, stream: &mut TcpStream) {
    let metadata = match std::fs::metadata(file_path) {
        Ok(m) => m,
        Err(_) => {
            let body = b"{\"error\":\"file not found\"}";
            write_response(
                stream,
                404,
                "Not Found",
                &[("Content-Type", "application/json".to_string())],
                Some(body),
            );
            return;
        }
    };
    if !metadata.is_file() {
        let body = b"{\"error\":\"not a file\"}";
        write_response(
            stream,
            400,
            "Bad Request",
            &[("Content-Type", "application/json".to_string())],
            Some(body),
        );
        return;
    }
    let file_len = metadata.len();
    let mut file = match std::fs::File::open(file_path) {
        Ok(f) => f,
        Err(_) => {
            let body = b"{\"error\":\"cannot open file\"}";
            write_response(
                stream,
                500,
                "Internal Server Error",
                &[("Content-Type", "application/json".to_string())],
                Some(body),
            );
            return;
        }
    };
    let headers = [
        ("Content-Type", "application/octet-stream".to_string()),
        ("Content-Length", file_len.to_string()),
    ];
    let mut header_block = String::new();
    header_block.push_str("HTTP/1.1 200 OK\r\n");
    for (k, v) in headers.iter() {
        header_block.push_str(k);
        header_block.push_str(": ");
        header_block.push_str(v);
        header_block.push_str("\r\n");
    }
    header_block.push_str("\r\n");
    let _ = stream.write_all(header_block.as_bytes());
    let mut buf = [0u8; 8192];
    loop {
        match file.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                if stream.write_all(&buf[..n]).is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
    let _ = stream.flush();
}

fn handle_upload(root: &Path, file_path: &Path, body: &[u8], stream: &mut TcpStream) {
    if let Some(parent) = file_path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let mut file = match std::fs::File::create(file_path) {
        Ok(f) => f,
        Err(_) => {
            let body = b"{\"error\":\"cannot create file\"}";
            write_response(
                stream,
                500,
                "Internal Server Error",
                &[("Content-Type", "application/json".to_string())],
                Some(body),
            );
            return;
        }
    };
    if let Err(_) = file.write_all(body) {
        let body = b"{\"error\":\"cannot write file\"}";
        write_response(
            stream,
            500,
            "Internal Server Error",
            &[("Content-Type", "application/json".to_string())],
            Some(body),
        );
        return;
    }
    let _ = file.flush();
    let body = b"{\"status\":\"ok\"}";
    write_response(
        stream,
        200,
        "OK",
        &[("Content-Type", "application/json".to_string())],
        Some(body),
    );
}

fn handle_info(stream: &mut TcpStream) {
    let body = b"{\"name\":\"ColourSwift Local HTTP\",\"status\":\"running\"}";
    write_response(
        stream,
        200,
        "OK",
        &[("Content-Type", "application/json".to_string())],
        Some(body),
    );
}

fn handle_delete(path: &Path, stream: &mut TcpStream) {
    let result = if path.is_dir() {
        std::fs::remove_dir_all(path)
    } else {
        std::fs::remove_file(path)
    };
    match result {
        Ok(_) => {
            let body = b"{\"status\":\"ok\"}";
            write_response(
                stream,
                200,
                "OK",
                &[("Content-Type", "application/json".to_string())],
                Some(body),
            );
        }
        Err(_) => {
            let body = b"{\"error\":\"delete failed\"}";
            write_response(
                stream,
                500,
                "Internal Server Error",
                &[("Content-Type", "application/json".to_string())],
                Some(body),
            );
        }
    }
}

fn handle_move_or_rename(from: &Path, to: &Path, stream: &mut TcpStream) {
    match std::fs::rename(from, to) {
        Ok(_) => {
            let body = b"{\"status\":\"ok\"}";
            write_response(
                stream,
                200,
                "OK",
                &[("Content-Type", "application/json".to_string())],
                Some(body),
            );
        }
        Err(_) => {
            let body = b"{\"error\":\"move failed\"}";
            write_response(
                stream,
                500,
                "Internal Server Error",
                &[("Content-Type", "application/json".to_string())],
                Some(body),
            );
        }
    }
}

fn handle_unauthorized(stream: &mut TcpStream) {
    let body = b"{\"error\":\"unauthorized\"}";
    write_response(
        stream,
        401,
        "Unauthorized",
        &[
            ("Content-Type", "application/json".to_string()),
            ("WWW-Authenticate", "X-Auth".to_string()),
        ],
        Some(body),
    );
}

fn handle_not_found(stream: &mut TcpStream) {
    let body = b"{\"error\":\"not found\"}";
    write_response(
        stream,
        404,
        "Not Found",
        &[("Content-Type", "application/json".to_string())],
        Some(body),
    );
}

fn handle_connection(mut stream: TcpStream, root: PathBuf, expected_pass: String) {
    let mut reader = match stream.try_clone() {
        Ok(s) => BufReader::new(s),
        Err(_) => return,
    };
    let mut request_line = String::new();
    if reader.read_line(&mut request_line).ok().unwrap_or(0) == 0 {
        return;
    }
    let request_line = request_line
        .trim_end_matches(|c| c == '\r' || c == '\n')
        .to_string();
    if request_line.is_empty() {
        return;
    }
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let path_and_query = parts.next().unwrap_or("/").to_string();

    let mut headers = Vec::<(String, String)>::new();
    loop {
        let mut line = String::new();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                let line_trim = line.trim_end_matches(|c| c == '\r' || c == '\n');
                if line_trim.is_empty() {
                    break;
                }
                if let Some((k, v)) = line_trim.split_once(':') {
                    headers.push((k.trim().to_string(), v.trim().to_string()));
                }
            }
            Err(_) => {
                return;
            }
        }
    }

    let mut content_length: usize = 0;
    if let Some(cl) = extract_header(&headers, "Content-Length") {
        if let Ok(n) = cl.parse::<usize>() {
            content_length = n;
        }
    }

    let mut body = Vec::new();
    if content_length > 0 {
        body.resize(content_length, 0u8);
        if reader.read_exact(&mut body).is_err() {
            return;
        }
    }

    let (path_only, _) = split_path_and_query(&path_and_query);

    let token_q = parse_query_param(&path_and_query, "token");
    let header_pass = extract_header(&headers, "X-Auth");
    let authed = match header_pass {
        Some(p) if p == expected_pass => true,
        _ => match token_q {
            Some(t) if t == expected_pass => true,
            _ => false,
        },
    };

    let requires_auth = matches!(
        path_only.as_str(),
        "/list" | "/download" | "/upload" | "/delete" | "/rename" | "/move"
    );

    if path_only == "/info" {
        handle_info(&mut stream);
        return;
    }

    if requires_auth && !authed {
        handle_unauthorized(&mut stream);
        return;
    }

    match (method.as_str(), path_only.as_str()) {
        ("GET", "/") => {
            let mut safe_pass = expected_pass.replace('\\', "\\\\");
            safe_pass = safe_pass.replace('\'', "\\'");
            let html = format!(
            "<!DOCTYPE html><html><head><meta charset='utf-8'><title>ColourSwift Explorer</title>
<style>
body {{ margin:0; padding:0; background:#f2f2f2; color:#111; font-family:Arial, sans-serif; }}
body.dark {{ background:#050505; color:#eee; }}
.header {{ background:#0057ff; color:white; padding:14px; font-size:20px; display:flex; justify-content:space-between; align-items:center; }}
.header button {{ background:white; color:#0057ff; border:none; padding:6px 10px; border-radius:6px; cursor:pointer; }}
body.dark .header {{ background:#111; }}
.container {{ max-width:900px; margin:auto; background:white; margin-top:20px; padding:20px; border-radius:10px; }}
body.dark .container {{ background:#181818; }}
.item {{ padding:10px 0; border-bottom:1px solid #ddd; display:flex; justify-content:space-between; align-items:center; gap:10px; }}
body.dark .item {{ border-color:#333; }}
.folder {{ font-weight:bold; color:#0057ff; cursor:pointer; }}
body.dark .folder {{ color:#7aa4ff; }}
.file {{ cursor:pointer; }}
.actions button {{ margin-left:4px; padding:4px 8px; border:none; background:#0057ff; color:white; border-radius:4px; cursor:pointer; font-size:12px; }}
body.dark .actions button {{ background:#3a6dff; }}
a {{ text-decoration:none; color:#0057ff; }}
body.dark a {{ color:#7aa4ff; }}
.upload-box {{ margin-top:20px; padding:10px; border:2px dashed #888; border-radius:10px; text-align:center; }}
body.dark .upload-box {{ border-color:#555; }}
input[type='file'] {{ display:block; margin:auto; margin-top:10px; }}
.thumb {{ height:32px; width:32px; object-fit:cover; border-radius:4px; margin-right:8px; }}
.thumb-holder {{ display:flex; align-items:center; gap:8px; }}
</style>
<script>
let password = '{}';
let currentPath = '/';

function toggleTheme() {{
    document.body.classList.toggle('dark');
}}

function isImage(name) {{
    const n = name.toLowerCase();
    return n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.gif') || n.endsWith('.webp');
}}

async function load(path) {{
    currentPath = path;
    const r = await fetch('/list?path=' + encodeURIComponent(path), {{
        headers: {{ 'X-Auth': password }}
    }});
    if (!r.ok) {{
        document.getElementById('list').innerHTML = '<p>Failed to load</p>';
        return;
    }}
    const data = await r.json();
    let html = '';
    if (path !== '/') {{
        let up = path.substring(0, path.lastIndexOf('/'));
        if (up === '') up = '/';
        html += `<div class='item'><span class='folder' onclick=\"load('${{up}}')\">.. (parent)</span></div>`;
    }}
    data.sort((a, b) => {{
        if (a.is_dir && !b.is_dir) return -1;
        if (!a.is_dir && b.is_dir) return 1;
        return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
    }});
    for (const e of data) {{
        const isDir = e.is_dir === true;
        const sizeLabel = isDir ? '' : formatSize(e.size || 0);
        if (isDir) {{
            const p = path === '/' ? '/' + e.name : path + '/' + e.name;
            html += `<div class='item'>
                        <div class='thumb-holder'>
                            <span class='folder' onclick=\"load('${{p}}')\">📁 ${{e.name}}</span>
                        </div>
                        <div class='actions'>
                            <button onclick=\"renameEntry('${{p}}','${{e.name}}')\">Rename</button>
                            <button onclick=\"moveEntry('${{p}}','${{e.name}}')\">Move</button>
                            <button onclick=\"deleteEntry('${{p}}')\">Delete</button>
                        </div>
                     </div>`;
        }} else {{
            const p = path === '/' ? '/' + e.name : path + '/' + e.name;
            let thumb = '';
            if (isImage(e.name)) {{
                thumb = `<img class='thumb' src='/download?path=${{encodeURIComponent(p)}}&token=${{encodeURIComponent(password)}}'>`;
            }}
            html += `<div class='item'>
                        <div class='thumb-holder'>
                            ${{thumb}}<span class='file'>📄 ${{e.name}}</span>
                        </div>
                        <div class='actions'>
                            <span>${{sizeLabel}}</span>
                            <a href='/download?path=${{encodeURIComponent(p)}}&token=${{encodeURIComponent(password)}}' target='_blank'><button>Download</button></a>
                            <button onclick=\"renameEntry('${{p}}','${{e.name}}')\">Rename</button>
                            <button onclick=\"moveEntry('${{p}}','${{e.name}}')\">Move</button>
                            <button onclick=\"deleteEntry('${{p}}')\">Delete</button>
                        </div>
                     </div>`;
        }}
    }}
    document.getElementById('list').innerHTML = html;
}}

function formatSize(bytes) {{
    if (bytes < 1024) return bytes + ' B';
    const kb = bytes / 1024;
    if (kb < 1024) return kb.toFixed(1) + ' KB';
    const mb = kb / 1024;
    if (mb < 1024) return mb.toFixed(1) + ' MB';
    const gb = mb / 1024;
    return gb.toFixed(1) + ' GB';
}}

async function deleteEntry(path) {{
    if (!confirm('Delete this item?')) return;
    await fetch('/delete?path=' + encodeURIComponent(path), {{
        method:'DELETE',
        headers: {{ 'X-Auth': password }}
    }});
    load(currentPath);
}}

async function renameEntry(path, name) {{
    const base = currentPath;
    const newName = prompt('New name', name);
    if (!newName) return;
    let target;
    if (base === '/') target = '/' + newName;
    else target = base + '/' + newName;
    await fetch('/rename?path=' + encodeURIComponent(path) + '&to=' + encodeURIComponent(target), {{
        method:'POST',
        headers: {{ 'X-Auth': password }}
    }});
    load(currentPath);
}}

async function moveEntry(path, name) {{
    const dest = prompt('Move to folder path', '/');
    if (!dest) return;
    let target;
    if (dest === '/') target = '/' + name;
    else target = dest + '/' + name;
    await fetch('/move?from=' + encodeURIComponent(path) + '&to=' + encodeURIComponent(target), {{
        method:'POST',
        headers: {{ 'X-Auth': password }}
    }});
    load(currentPath);
}}

async function triggerUpload() {{
    const input = document.getElementById('fileInput');
    const files = input.files;
    if (!files || files.length === 0) return;
    const path = currentPath;
    const tasks = [];
    for (let i = 0; i < files.length; i++) {{
        const f = files[i];
        const bufPromise = f.arrayBuffer().then(buf => {{
            let target = path === '/' ? '/' + f.name : path + '/' + f.name;
            return fetch('/upload?path=' + encodeURIComponent(target), {{
                method:'POST',
                headers: {{ 'X-Auth': password }},
                body: buf
            }});
        }});
        tasks.push(bufPromise);
    }}
    await Promise.all(tasks);
    input.value = '';
    load(path);
}}

window.onload = () => load('/');
</script>
</head>
<body>
<div class='header'>
  <span>ColourSwift Local Server</span>
  <button onclick='toggleTheme()'>Toggle theme</button>
</div>
<div class='container'>
  <h2>Web File Explorer</h2>
  <div id='list'></div>
  <div class='upload-box'>
    <h3>Upload Files</h3>
    <input id='fileInput' type='file' multiple>
    <button onclick='triggerUpload()'>Upload selected</button>
  </div>
</div>
</body></html>",
            expected_pass
        );

            write_response(
                &mut stream,
                200,
                "OK",
                &[("Content-Type", "text/html; charset=utf-8".to_string())],
                Some(html.as_bytes()),
            );
        }

        ("GET", "/list") => {
            let rel = parse_query_param(&path_and_query, "path").unwrap_or("/".to_string());
            let target = match sanitize_path(&root, &rel) {
                Some(p) => p,
                None => {
                    let body = b"{\"error\":\"invalid path\"}";
                    write_response(
                        &mut stream,
                        400,
                        "Bad Request",
                        &[("Content-Type", "application/json".to_string())],
                        Some(body),
                    );
                    return;
                }
            };
            if !target.is_dir() {
                let body = b"{\"error\":\"not a directory\"}";
                write_response(
                    &mut stream,
                    400,
                    "Bad Request",
                    &[("Content-Type", "application/json".to_string())],
                    Some(body),
                );
                return;
            }
            handle_list(&root, &target, &mut stream);
        }

        ("GET", "/download") => {
            let rel = parse_query_param(&path_and_query, "path").unwrap_or("/".to_string());
            let target = match sanitize_path(&root, &rel) {
                Some(p) => p,
                None => {
                    let body = b"{\"error\":\"invalid path\"}";
                    write_response(
                        &mut stream,
                        400,
                        "Bad Request",
                        &[("Content-Type", "application/json".to_string())],
                        Some(body),
                    );
                    return;
                }
            };
            handle_download(&root, &target, &mut stream);
        }

        ("POST", "/upload") => {
            let rel =
                parse_query_param(&path_and_query, "path").unwrap_or("/upload.bin".to_string());
            let target = match sanitize_path(&root, &rel) {
                Some(p) => p,
                None => {
                    let body = b"{\"error\":\"invalid path\"}";
                    write_response(
                        &mut stream,
                        400,
                        "Bad Request",
                        &[("Content-Type", "application/json".to_string())],
                        Some(body),
                    );
                    return;
                }
            };
            handle_upload(&root, &target, &body, &mut stream);
        }

        ("DELETE", "/delete") => {
            let rel = parse_query_param(&path_and_query, "path").unwrap_or("/".to_string());
            let target = match sanitize_path(&root, &rel) {
                Some(p) => p,
                None => {
                    let body = b"{\"error\":\"invalid path\"}";
                    write_response(
                        &mut stream,
                        400,
                        "Bad Request",
                        &[("Content-Type", "application/json".to_string())],
                        Some(body),
                    );
                    return;
                }
            };
            if !target.exists() {
                let body = b"{\"error\":\"not found\"}";
                write_response(
                    &mut stream,
                    404,
                    "Not Found",
                    &[("Content-Type", "application/json".to_string())],
                    Some(body),
                );
                return;
            }
            handle_delete(&target, &mut stream);
        }

        ("POST", "/rename") => {
            let from_rel = parse_query_param(&path_and_query, "path").unwrap_or("/".to_string());
            let to_rel = parse_query_param(&path_and_query, "to").unwrap_or("/".to_string());
            let from = match sanitize_path(&root, &from_rel) {
                Some(p) => p,
                None => {
                    let body = b"{\"error\":\"invalid source\"}";
                    write_response(
                        &mut stream,
                        400,
                        "Bad Request",
                        &[("Content-Type", "application/json".to_string())],
                        Some(body),
                    );
                    return;
                }
            };
            let to = match sanitize_path(&root, &to_rel) {
                Some(p) => p,
                None => {
                    let body = b"{\"error\":\"invalid target\"}";
                    write_response(
                        &mut stream,
                        400,
                        "Bad Request",
                        &[("Content-Type", "application/json".to_string())],
                        Some(body),
                    );
                    return;
                }
            };
            handle_move_or_rename(&from, &to, &mut stream);
        }

        ("POST", "/move") => {
            let from_rel = parse_query_param(&path_and_query, "from").unwrap_or("/".to_string());
            let to_rel = parse_query_param(&path_and_query, "to").unwrap_or("/".to_string());
            let from = match sanitize_path(&root, &from_rel) {
                Some(p) => p,
                None => {
                    let body = b"{\"error\":\"invalid source\"}";
                    write_response(
                        &mut stream,
                        400,
                        "Bad Request",
                        &[("Content-Type", "application/json".to_string())],
                        Some(body),
                    );
                    return;
                }
            };
            let to = match sanitize_path(&root, &to_rel) {
                Some(p) => p,
                None => {
                    let body = b"{\"error\":\"invalid target\"}";
                    write_response(
                        &mut stream,
                        400,
                        "Bad Request",
                        &[("Content-Type", "application/json".to_string())],
                        Some(body),
                    );
                    return;
                }
            };
            handle_move_or_rename(&from, &to, &mut stream);
        }

        _ => {
            handle_not_found(&mut stream);
        }
    }
}

fn http_server_main(addr: SocketAddr, root: PathBuf, password: String, shutdown: Arc<AtomicBool>) {
    let listener = match TcpListener::bind(addr) {
        Ok(l) => l,
        Err(_) => return,
    };
    let _ = std::fs::create_dir_all(&root);
    let _ = listener.set_nonblocking(true);
    while !shutdown.load(Ordering::SeqCst) {
        match listener.accept() {
            Ok((stream, _)) => {
                let root_clone = root.clone();
                let pass_clone = password.clone();
                thread::spawn(move || {
                    handle_connection(stream, root_clone, pass_clone);
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
pub extern "C" fn http_start_with_root(port: i32, root: *const c_char, password: *const c_char) {
    let root_path = PathBuf::from(cstring(root));
    let _ = std::fs::create_dir_all(&root_path);

    let pass = cstring(password);

    let mut lock = HTTP_STATE.lock().unwrap();
    if lock.is_some() {
        return;
    }

    let shutdown_flag = Arc::new(AtomicBool::new(false));
    let shutdown_clone = shutdown_flag.clone();

    let addr = SocketAddr::from(([0, 0, 0, 0], port as u16));

    let handle = thread::spawn(move || {
        http_server_main(addr, root_path, pass, shutdown_clone);
    });

    *lock = Some(HttpHandle {
        shutdown: shutdown_flag,
        thread: Some(handle),
    });
}

#[no_mangle]
pub extern "C" fn http_start(port: i32, password: *const c_char) {
    let dot = std::ffi::CString::new(".").unwrap();
    http_start_with_root(port, dot.as_ptr(), password);
}

#[no_mangle]
pub extern "C" fn http_stop() {
    let mut lock = HTTP_STATE.lock().unwrap();
    if let Some(handle) = lock.as_mut() {
        handle.shutdown.store(true, Ordering::SeqCst);
        if let Some(join) = handle.thread.take() {
            let _ = join.join();
        }
    }
    *lock = None;
}

#[no_mangle]
pub extern "C" fn http_status() -> i32 {
    let lock = HTTP_STATE.lock().unwrap();
    if lock.is_some() {
        1
    } else {
        0
    }
}
