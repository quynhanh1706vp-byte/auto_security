#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runsv2_sort_${TS}"
echo "[BACKUP] ${W}.bak_runsv2_sort_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_RUNS_V2_PREFER_NONZERO_SORT_V1"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

# Chỉ patch khi đã có block realdata/runs_v2 tồn tại (tránh chèn nhầm)
anchor = "VSP_TABS3_REALDATA_ENRICH_P1_V2"
idx = s.find(anchor)
if idx < 0:
    print("[ERR] cannot find anchor:", anchor)
    raise SystemExit(2)

tail = s[idx:]

# Tìm return json của runs_v2 có dạng: return __wsgi_json({"ok": True, "items": items, ...})
m = re.search(r'(?m)^(?P<ind>[ \t]*)return\s+__wsgi_json\(\{\s*"ok"\s*:\s*True\s*,\s*"items"\s*:\s*items\b', tail)
if not m:
    print("[ERR] cannot locate runs_v2 return __wsgi_json({\"ok\":True,\"items\":items...}) after anchor")
    raise SystemExit(2)

ind = m.group("ind")
insert_pos = idx + m.start()

inject = (
    f"{ind}# {marker}\n"
    f"{ind}# Prefer runs that actually have findings, then newest mtime.\n"
    f"{ind}try:\n"
    f"{ind}    items.sort(key=lambda r: (1 if r.get('has_findings') else 0, int(r.get('mtime', 0) or 0)), reverse=True)\n"
    f"{ind}except Exception:\n"
    f"{ind}    pass\n\n"
)

s2 = s[:insert_pos] + inject + s[insert_pos:]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted:", marker)
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart (no sudo) =="
# dùng script start single-owner của bạn nếu có, fallback: không restart
if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh || true
else
  echo "[WARN] missing bin/p1_ui_8910_single_owner_start_v2.sh -> please restart manually"
fi

echo "== verify (first item should have has_findings:true if any exists) =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS "$BASE/api/ui/runs_v2?limit=3" | head -c 900; echo
echo "[DONE] runs_v2 now prefers nonzero findings first."
