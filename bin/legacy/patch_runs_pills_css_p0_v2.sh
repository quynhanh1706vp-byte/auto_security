#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

CSS="static/css/vsp_2025_dark.css"
[ -f "$CSS" ] || CSS="$(ls -1 static/css/*.css 2>/dev/null | head -n1 || true)"
[ -n "${CSS:-}" ] || { echo "[ERR] cannot find css under static/css"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$CSS" "${CSS}.bak_pills_v2_${TS}"
echo "[BACKUP] ${CSS}.bak_pills_v2_${TS}"
echo "[CSS]=$CSS"

export CSSF="$CSS"

python3 - <<'PY'
import os
from pathlib import Path

cssf=os.environ.get("CSSF","").strip()
if not cssf:
    raise SystemExit("[ERR] missing CSSF env")
p=Path(cssf)
if not p.exists():
    raise SystemExit(f"[ERR] css not found: {p}")

s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_RUNS_PILLS_CSS_P0_V2"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon = r"""
/* VSP_RUNS_PILLS_CSS_P0_V2 */
.pill{
  display:inline-flex;
  align-items:center;
  gap:6px;
  padding:2px 8px;
  border-radius:999px;
  font-size:12px;
  line-height:18px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.06);
  color:rgba(255,255,255,0.80);
  vertical-align:middle;
  margin-left:6px;
}
.pill-muted{ opacity:0.72; }
.pill-ok{ border-color: rgba(0,255,153,0.25); background: rgba(0,255,153,0.08); }
.pill-warn{ border-color: rgba(255,204,0,0.25); background: rgba(255,204,0,0.08); }
.pill-bad{ border-color: rgba(255,80,80,0.25); background: rgba(255,80,80,0.08); }
"""
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] wrote:", p)
PY

sudo systemctl restart vsp-ui-8910.service
sleep 0.6
echo "[OK] restarted 8910"
