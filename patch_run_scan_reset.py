from pathlib import Path

path = Path("app.py")
text = path.read_text()

start = text.find('@app.route("/run", methods=["POST"])')
if start == -1:
    print("[ERR] Không tìm thấy @app.route('/run', ...) trong app.py")
    raise SystemExit(1)

end = text.find("\n@app.route", start + 1)
if end == -1:
    end = len(text)

new_block = '''@app.route("/run", methods=["POST"])
def run_scan():
    """Handle scan request from UI: resolve SRC, set env, call wrapper, then redirect."""
    global DEFAULT_SRC

    # Lấy SRC thô từ form, nếu trống thì dùng DEFAULT_SRC hiện tại
    raw_src = (request.form.get("src") or "").strip()
    src_input = raw_src or DEFAULT_SRC

    # Profile (fast/aggr) & mode (online/offline)
    profile = (request.form.get("profile") or "Aggressive").lower()
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

    # Cập nhật DEFAULT_SRC để index() dùng làm default cho ô SRC
    DEFAULT_SRC = picked_src

    # Sau khi scan xong, quay lại dashboard với profile/mode đúng (không truyền src)
    return redirect(url_for("index", profile=profile, mode=mode))

'''

text = text[:start] + new_block + text[end:]
path.write_text(text)
print("[OK] Đã ghi đè toàn bộ handler /run (run_scan).")
