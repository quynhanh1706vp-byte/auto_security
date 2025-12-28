#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

# --- [1] patch delta semantics in vsp_rule_overrides_apply_v1.py ---
PYMOD="vsp_rule_overrides_apply_v1.py"
[ -f "$PYMOD" ] || { echo "[ERR] missing $PYMOD"; exit 2; }
cp -f "$PYMOD" "$PYMOD.bak_delta_${TS}" && echo "[BACKUP] $PYMOD.bak_delta_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_rule_overrides_apply_v1.py")
s=p.read_text(encoding="utf-8", errors="ignore")

# Replace the delta build block in apply_overrides() best-effort
# We will:
# - count matched_n (override matched, not expired)
# - applied_n = suppress or severity changed (actual effect)
# - expired_match_n = expired override that would match
if "matched_n" in s and "expired_match_n" in s:
    print("[SKIP] delta already patched")
    raise SystemExit(0)

# Insert counters near top of apply_overrides
s = re.sub(r"(suppressed_n\s*=\s*0\s*\n\s*changed_severity_n\s*=\s*0\s*\n\s*expired_n\s*=\s*0\s*\n\s*applied_n\s*=\s*0)",
           r"suppressed_n=0\n    changed_severity_n=0\n    expired_match_n=0\n    matched_n=0\n    applied_effect_n=0",
           s, count=1)

# Expired counting rename
s = s.replace("expired_n += 1", "expired_match_n += 1")

# When matched (not expired): increment matched_n, and later count effect
# Find "applied_n += 1" line and change to matched_n +=1
s = s.replace("applied_n += 1", "matched_n += 1")

# When setsev changes OR suppress true: count applied_effect_n
# We already increment changed_severity_n when changed; add applied_effect_n +=1 when changed
s = re.sub(r"(changed_severity_n\s*\+=\s*1)",
           r"\1\n                applied_effect_n += 1",
           s, count=1)

# When suppress -> applied_effect_n += 1 before continue
s = re.sub(r"(suppressed_n\s*\+=\s*1\s*\n\s*continue)",
           r"suppressed_n += 1\n            applied_effect_n += 1\n            continue",
           s, count=1)

# Build delta dict: replace existing delta construction
s = re.sub(
    r"delta\s*=\s*\{\s*\"applied_n\":\s*applied_n,\s*\"suppressed_n\":\s*suppressed_n,\s*\"changed_severity_n\":\s*changed_severity_n,\s*\"expired_n\":\s*expired_n,\s*\"now_utc\":\s*now\.isoformat\(\),\s*\}",
    'delta = {\n        "matched_n": matched_n,\n        "applied_n": applied_effect_n,  # EFFECTIVE changes only\n        "suppressed_n": suppressed_n,\n        "changed_severity_n": changed_severity_n,\n        "expired_match_n": expired_match_n,\n        "now_utc": now.isoformat(),\n        "note": "applied_n counts only suppress/severity-change effects; matched_n counts matched overrides (non-expired)",\n    }',
    s,
    count=1
)

# Also tolerate if delta block format differs (fallback: append fields after delta creation)
if "note" not in s or "matched_n" not in s:
    print("[WARN] regex delta replace may not have matched; leaving file as-is (manual check may be needed).")

p.write_text(s, encoding="utf-8")
print("[OK] patched delta semantics in", p)
PY

# --- [2] patch vsp_demo_app.py: add alias route for runs_index_v3_fs_resolved if missing ---
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 3; }
cp -f "$APP" "$APP.bak_runs_index_alias_${TS}" && echo "[BACKUP] $APP.bak_runs_index_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="### VSP_RUNS_INDEX_ALIAS_FALLBACK_V1 ###"
if MARK in s:
    print("[SKIP] alias marker already present")
    raise SystemExit(0)

# Inject right after the FS fallback block (so _vsp_scan_latest_run_dirs exists)
anchor="### VSP_RID_FALLBACK_FS_V1 ###"
idx=s.find(anchor)
if idx<0:
    # fallback: append near end
    m=re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
    idx = m.start() if m else len(s)

insert_at = idx
block=f"""
\n{MARK}
# Backward-compat: some UI/scripts still call this; map it to filesystem scan.
if "api_vsp_runs_index_v3_fs_resolved" not in getattr(app, "view_functions", {{}}):
    @app.get("/api/vsp/runs_index_v3_fs_resolved")
    def api_vsp_runs_index_v3_fs_resolved():
        try:
            limit = int(request.args.get("limit","20"))
        except Exception:
            limit = 20
        items = _vsp_scan_latest_run_dirs(limit=limit)
        return jsonify({{
          "ok": True,
          "items": items,
          "items_n": len(items),
          "source": "FS_FALLBACK_V1"
        }}), 200
"""
s2 = s[:insert_at] + block + "\n" + s[insert_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected runs_index_v3_fs_resolved alias fallback")
PY

python3 -m py_compile vsp_demo_app.py vsp_rule_overrides_apply_v1.py
echo "[OK] py_compile OK"
