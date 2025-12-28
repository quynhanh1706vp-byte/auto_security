from pathlib import Path

path = Path("app.py")
text = path.read_text()

marker = "def run_scan("
idx = text.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy def run_scan trong app.py")
    raise SystemExit(1)

# Tìm tới decorator tiếp theo (@app.route ...) để cắt phần cũ
idx2 = text.find("\n@app.route", idx)
if idx2 == -1:
    idx2 = len(text)

new_func = '''def run_scan():
    """Handle scan request from UI: resolve SRC, set env, call wrapper, then redirect."""
    # Lấy SRC thô từ form, nếu trống thì dùng DEFAULT_SRC
    raw_src = (request.form.get("src") or "").strip()
    src_input = raw_src or DEFAULT_SRC

    # Profile (fast/aggr) & mode (online/offline)
    profile = (request.form.get("profile") or "aggr").lower()
    mode = (request.form.get("mode") or "offline").lower()

    # Auto-pick deep src (thư mục code) nếu có
    try:
        picked_src = auto_pick_deep_src(src_input)
    except Exception:
        picked_src = src_input

    print(f"[UI] run_scan: SRC input = {src_input}, picked = {picked_src}", flush=True)

    # Map profile → LEVEL cho bundle
    level = "aggr" if profile in ("aggr", "aggressive", "deep") else "fast"
    # Map mode → NO_NET
    no_net = "1" if mode in ("offline", "off", "no-net", "no_net") else "0"

    # Truyền SRC/LEVEL/NO_NET vào env cho SCAN_WRAPPER
    env = os.environ.copy()
    env.update({
        "SRC": picked_src,
        "LEVEL": level,
        "NO_NET": no_net,
    })

    try:
        subprocess.run(
            [SCAN_WRAPPER],
            env=env,
            check=False,
        )
    except Exception as e:
        print(f"[UI][ERROR] run_scan subprocess failed: {e}", flush=True)

    # Sau khi scan xong, quay lại dashboard với SRC/profile/mode đúng
    return redirect(url_for("index", src=picked_src, profile=profile, mode=mode))

'''

text2 = text[:idx] + new_func + text[idx2:]
path.write_text(text2)
print("[OK] Đã thay thế hàm run_scan với bản mới (truyền SRC/LEVEL/NO_NET cho wrapper).")
