#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need python3; need date; need grep; need awk; need sed; need curl; need head

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [0] detect ExecStart and app spec =="
EX="$(systemctl show -p ExecStart --value "$SVC" | head -n 1)"
echo "[INFO] ExecStart=$EX"

# Try to extract gunicorn app spec token: last non-option token that contains ':'
APP_SPEC="$(echo "$EX" | tr ' ' '\n' | grep -E '^[A-Za-z0-9_.-]+:[A-Za-z0-9_]+$' | tail -n 1 || true)"
if [ -z "$APP_SPEC" ]; then
  # fallback: sometimes it is quoted or appended
  APP_SPEC="$(echo "$EX" | grep -oE '[A-Za-z0-9_.-]+:[A-Za-z0-9_]+' | tail -n 1 || true)"
fi

if [ -z "$APP_SPEC" ]; then
  echo "[ERR] cannot extract gunicorn APP_SPEC (module:var) from ExecStart"
  echo "[HINT] run: systemctl show -p ExecStart --value $SVC"
  exit 2
fi

MOD="${APP_SPEC%%:*}"
VAR="${APP_SPEC##*:}"
echo "[INFO] APP_SPEC=$APP_SPEC"
echo "[INFO] MOD=$MOD  VAR=$VAR"

echo "== [1] locate module file under repo =="
REL="$(echo "$MOD" | tr '.' '/')"
CAND1="./${REL}.py"
FILE=""
if [ -f "$CAND1" ]; then
  FILE="$CAND1"
else
  # search anywhere in repo
  FILE="$(find . -type f -name "$(basename "$REL").py" | grep -F "/${REL}.py" | head -n 1 || true)"
  if [ -z "$FILE" ]; then
    FILE="$(find . -type f -name "$(basename "$REL").py" | head -n 1 || true)"
  fi
fi

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "[ERR] cannot locate python file for module: $MOD (tried $CAND1 and find)"
  exit 2
fi
echo "[INFO] entry file: $FILE"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$FILE" "${FILE}.bak_trend_entry_${TS}"
echo "[BACKUP] ${FILE}.bak_trend_entry_${TS}"

python3 - "$FILE" "$VAR" <<'PY'
from pathlib import Path
import sys, textwrap, re

p = Path(sys.argv[1])
var_name = sys.argv[2]
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P2_TREND_V1_ENTRY_OVERRIDE_V1D"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

patch = textwrap.dedent(f"""
# --- {MARK} (auto-injected) ---
def _vsp_install_trend_override_on(obj):
    # install on any Flask-like object (has route/before_request)
    if obj is None:
        return False
    if not (hasattr(obj, "route") and hasattr(obj, "before_request")):
        return False
    if getattr(obj, "_vsp_trend_override_installed", False):
        return True
    obj._vsp_trend_override_installed = True

    from flask import request, jsonify
    import os, json, datetime

    def _load_json(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return None

    def _total_from_gate(j):
        if not isinstance(j, dict): return None
        for k in ("total", "total_findings", "findings_total", "total_unified"):
            v = j.get(k)
            if isinstance(v, int): return v
        c = j.get("counts") or j.get("severity_counts") or j.get("by_severity")
        if isinstance(c, dict):
            sm = 0
            for vv in c.values():
                if isinstance(vv, int): sm += vv
            return sm
        return None

    def _list_run_dirs(limit):
        roots = ["/home/test/Data/SECURITY_BUNDLE/out_ci", "/home/test/Data/SECURITY_BUNDLE/out"]
        roots = [r for r in roots if os.path.isdir(r)]
        dirs = []
        for r in roots:
            try:
                for name in os.listdir(r):
                    if not (name.startswith("VSP_") or name.startswith("RUN_")):
                        continue
                    full = os.path.join(r, name)
                    if os.path.isdir(full):
                        try:
                            mt = os.path.getmtime(full)
                        except Exception:
                            mt = 0
                        dirs.append((mt, name, full))
            except Exception:
                pass
        dirs.sort(key=lambda x: x[0], reverse=True)
        return dirs[: max(limit*3, limit)]

    @obj.before_request
    def _vsp_before_request_trend_override():
        if request.path != "/api/vsp/trend_v1":
            return None

        rid = (request.args.get("rid") or "").strip()
        try:
            limit = int(request.args.get("limit") or 20)
        except Exception:
            limit = 20
        if limit < 5: limit = 5
        if limit > 80: limit = 80

        points = []
        for mt, name, d in _list_run_dirs(limit):
            gate = _load_json(os.path.join(d, "run_gate_summary.json")) or _load_json(os.path.join(d, "reports", "run_gate_summary.json"))
            total = _total_from_gate(gate)
            if total is None:
                fu = _load_json(os.path.join(d, "findings_unified.json")) or _load_json(os.path.join(d, "reports", "findings_unified.json"))
                if isinstance(fu, list):
                    total = len(fu)
                elif isinstance(fu, dict) and isinstance(fu.get("findings"), list):
                    total = len(fu.get("findings"))
            if total is None:
                continue
            ts = datetime.datetime.fromtimestamp(mt).isoformat(timespec="seconds")
            label = datetime.datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M")
            points.append({{"label": label, "run_id": name, "total": int(total), "ts": ts}})
            if len(points) >= limit:
                break

        return jsonify({{
            "ok": True,
            "marker": "{MARK}",
            "rid_requested": rid,
            "limit": limit,
            "points": points
        }})

    return True

def _vsp_install_trend_override_anywhere():
    g = globals()
    # 1) exact exported var from gunicorn (common)
    cand = g.get("{var_name}")
    if _vsp_install_trend_override_on(cand):
        return
    # 2) common names
    for k in ("app","application","flask_app","APP"):
        if _vsp_install_trend_override_on(g.get(k)):
            return
    # 3) scan all globals for Flask-like
    for v in list(g.values()):
        try:
            if _vsp_install_trend_override_on(v):
                return
        except Exception:
            pass

try:
    _vsp_install_trend_override_anywhere()
except Exception:
    pass
# --- end {MARK} ---
""").lstrip("\n")

p.write_text(s + ("\n\n" if not s.endswith("\n") else "\n") + patch, encoding="utf-8")
print("[OK] appended override into", p)
PY

python3 -m py_compile "$FILE"
echo "[OK] py_compile OK"

echo "== [2] restart service =="
sudo systemctl restart "$SVC"

echo "== [3] smoke trend_v1 (must be ok:true + marker) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=5" | head -c 260; echo
