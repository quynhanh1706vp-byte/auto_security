from pathlib import Path

f = Path("vsp_demo_app.py")
txt = f.read_text(encoding="utf-8")

backup = Path("vsp_demo_app.py.bak_whoami_cleanup_v2")
backup.write_text(txt, encoding="utf-8")
print("[WHOAMI_CLEAN_V2] Backup saved:", backup)

lines = txt.splitlines()
out_lines = []
seen = 0
skipping = False

for line in lines:
    # Gặp dòng route whoami
    if '@app.route("/__vsp_ui_whoami"' in line:
        seen += 1
        if seen == 1:
            # Giữ block đầu tiên
            out_lines.append(line)
            skipping = False
        else:
            # Bắt đầu bỏ block thứ 2 trở đi
            print("[WHOAMI_CLEAN_V2] Removing extra whoami block...")
            skipping = True
        continue

    if skipping:
        # Đang bỏ block extra:
        # dừng bỏ khi gặp route mới khác whoami
        if line.strip().startswith("@app.route(") and "/__vsp_ui_whoami" not in line:
            skipping = False
            out_lines.append(line)
        else:
            # vẫn trong block dư → bỏ
            continue
    else:
        out_lines.append(line)

new_txt = "\n".join(out_lines)
f.write_text(new_txt, encoding="utf-8")
print("[WHOAMI_CLEAN_V2] Done.")
