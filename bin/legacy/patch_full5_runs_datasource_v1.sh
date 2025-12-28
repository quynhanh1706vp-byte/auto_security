#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/my_flask_app/my_flask_app/SECURITY_BUNDLE_FULL_5_PAGES.html"

echo "[i] ROOT = $ROOT"
echo "[i] APP  = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy file: $APP" >&2
  exit 1
fi

# Backup trước khi sửa
BACKUP="${APP}.bak_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BACKUP"
echo "[OK] Đã backup: $BACKUP"

python3 - "$APP" <<'PY'
import sys, pathlib, re, textwrap

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

changed = False

# 1) Ẩn <h1>Dashboard</h1> ngay trước heading Data Source
pattern = re.compile(
    r'\s*<h1[^>]*>\s*Dashboard\s*</h1>\s*(?=(?:\s*<!--.*?-->)*\s*<h1[^>]*>\s*Data Source\s*</h1>)',
    re.IGNORECASE | re.DOTALL,
)
new_data, n = pattern.subn("\n", data)
if n:
    print(f"[OK] Ẩn heading 'Dashboard' trong Data Source ({n} lần).")
    data = new_data
    changed = True
else:
    print("[WARN] Không tìm thấy heading 'Dashboard' gần phần Data Source – bỏ qua.")

# 2) Chèn CSS cho sb-pill-disabled & Sample Findings card trước </style>
css_snippet = textwrap.dedent("""
    /* === Runs & Reports / Data Source tweaks (v1) ====================== */

    /* Disabled export pill (no file available) */
    .sb-pill-disabled {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 0.25rem 1.25rem;
      border-radius: 999px;
      font-size: 0.85rem;
      font-weight: 600;
      background: rgba(16, 185, 129, 0.18);
      color: rgba(226, 232, 240, 0.55);
      cursor: default;
      pointer-events: none;
    }
    .sb-pill-disabled:hover {
      box-shadow: none;
      transform: none;
    }

    /* Sample Findings – compact cards */
    .sb-finding-list {
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
      margin-top: 1rem;
    }
    .sb-finding-card {
      padding: 0.85rem 1.0rem;
      border-radius: 0.9rem;
      border: 1px solid rgba(148, 163, 184, 0.25);
      box-shadow: 0 18px 38px rgba(0, 0, 0, 0.55);
      font-size: 0.9rem;
    }
    .sb-finding-card:hover {
      border-color: rgba(52, 211, 153, 0.6);
      box-shadow: 0 24px 60px rgba(22, 163, 74, 0.75);
    }
    .sb-finding-critical {
      background: radial-gradient(circle at top left,
                  rgba(248, 113, 113, 0.35),
                  rgba(15, 23, 42, 0.96));
    }
    .sb-finding-high {
      background: radial-gradient(circle at top left,
                  rgba(248, 171, 88, 0.38),
                  rgba(15, 23, 42, 0.96));
    }
    .sb-finding-title {
      font-weight: 600;
      color: #e5e7eb;
      margin-bottom: 0.15rem;
    }
    .sb-finding-meta {
      font-size: 0.8rem;
      color: rgba(148, 163, 184, 0.95);
    }
    .sb-finding-meta code {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      font-size: 0.78rem;
      background: rgba(15, 23, 42, 0.9);
      padding: 0.05rem 0.35rem;
      border-radius: 0.35rem;
    }
    .sb-finding-badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 0.18rem 0.7rem;
      border-radius: 999px;
      font-size: 0.72rem;
      font-weight: 700;
      letter-spacing: 0.06em;
      margin-right: 0.6rem;
    }
    .sb-finding-badge-critical {
      background: #b91c1c;
      color: #fee2e2;
    }
    .sb-finding-badge-high {
      background: #ea580c;
      color: #ffedd5;
    }
    .sb-finding-toolbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 0.35rem;
      font-size: 0.8rem;
      color: rgba(148, 163, 184, 0.95);
    }
    .sb-finding-tool {
      text-transform: uppercase;
      opacity: 0.9;
    }
    .sb-finding-link {
      font-size: 0.78rem;
      color: #22c55e;
      text-decoration: none;
      border-radius: 999px;
      border: 1px solid rgba(34, 197, 94, 0.7);
      padding: 0.12rem 0.7rem;
    }
    .sb-finding-link:hover {
      background: rgba(22, 163, 74, 0.16);
    }
""")

if ".sb-pill-disabled" not in data and ".sb-finding-card" not in data:
    idx = data.rfind("</style>")
    if idx != -1:
        data = data[:idx] + css_snippet + data[idx:]
        changed = True
        print("[OK] Đã chèn CSS .sb-pill-disabled & .sb-finding-*. ")
    else:
        print("[WARN] Không tìm thấy </style> – không thể chèn CSS.")
else:
    print("[INFO] Có vẻ CSS cho phần này đã tồn tại – bỏ qua chèn CSS.")

if changed:
    path.write_text(data, encoding="utf-8")
    print("[DONE] Đã patch SECURITY_BUNDLE_FULL_5_PAGES.html (v1).")
else:
    print("[INFO] Không có thay đổi nào được áp dụng (file đã giống bản v1?).")
PY
PY
