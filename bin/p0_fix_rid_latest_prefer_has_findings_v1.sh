#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

BAK="${PYF}.bak_ridlatest_strict_${TS}"
cp -f "$PYF" "$BAK"
echo "[BACKUP] $BAK"

export MARK="VSP_P0_RID_LATEST_PREFER_HAS_FINDINGS_V1"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, os

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK=os.environ["MARK"]

if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

block=textwrap.dedent("""
# ===================== {MARK} =====================
try:
    import json, time, re
    from pathlib import Path
    from flask import jsonify

    _app = globals().get("app") or globals().get("application")
    if _app is None:
        print("[{MARK}] WARN: cannot find app/application in globals()")
    else:
        def _rl_is_rid(v: str) -> bool:
            if not v: return False
            v=str(v).strip()
            if len(v)<6 or len(v)>140: return False
            if any(c.isspace() for c in v): return False
            if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.:-]+$", v): return False
            if not any(ch.isdigit() for ch in v): return False
            return True

        def _rl_roots():
            roots=[
                Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
                Path("/home/test/Data/SECURITY_BUNDLE/out"),
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
            ]
            base=Path("/home/test/Data")
            if base.is_dir():
                try:
                    for d in base.iterdir():
                        if d.is_dir() and d.name.startswith("SECURITY"):
                            roots.append(d/"out_ci")
                            roots.append(d/"out")
                except Exception:
                    pass
            return roots

        def _rl_has_core_artifacts(run_dir: Path):
            # prefer root findings_unified.json (dashboard expects this today)
            prefs = [
                run_dir/"findings_unified.json",
                run_dir/"run_gate_summary.json",
                run_dir/"reports"/"findings_unified.json",
                run_dir/"reports"/"findings_unified.csv",
            ]
            for fp in prefs:
                try:
                    if fp.is_file() and fp.stat().st_size > 0:
                        return True, fp.name if fp.parent==run_dir else str(fp.relative_to(run_dir))
                except Exception:
                    pass
            return False, ""

        def _rl_pick_latest_with_artifacts(limit_scan=600):
            cand=[]
            for r in _rl_roots():
                try:
                    if not r.is_dir(): 
                        continue
                    for d in r.iterdir():
                        if not d.is_dir(): 
                            continue
                        rid=d.name
                        if not _rl_is_rid(rid): 
                            continue
                        if not (rid.startswith("RUN_") or "VSP" in rid or "_RUN_" in rid):
                            continue
                        try:
                            cand.append((d.stat().st_mtime, rid, d))
                        except Exception:
                            pass
                except Exception:
                    continue
            cand.sort(reverse=True, key=lambda t: t[0])

            checked=0
            for mt, rid, d in cand[:max(1, int(limit_scan))]:
                ok, why = _rl_has_core_artifacts(d)
                checked += 1
                if ok:
                    return (mt, rid, str(d), why), len(cand), checked
            return None, len(cand), checked

        def vsp_rid_latest_prefer_has_findings_v1():
            cache_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/_rid_latest_cache.json")
            cache_path.parent.mkdir(parents=True, exist_ok=True)

            best, total, checked = _rl_pick_latest_with_artifacts()
            if best:
                mt, rid, pth, why = best
                try:
                    cache_path.write_text(json.dumps({"rid": rid, "path": pth, "mtime": mt, "why": why, "ts": time.time()}, ensure_ascii=False),
                                          encoding="utf-8")
                except Exception:
                    pass
                return jsonify({"ok": True, "rid": rid, "path": pth, "mtime": mt, "stale": False,
                                "candidates": total, "checked": checked, "why": why})

            # fallback cache (still must be valid)
            try:
                if cache_path.is_file():
                    j=json.loads(cache_path.read_text(encoding="utf-8", errors="replace") or "{}")
                    rid=(j.get("rid") or "").strip()
                    pth=(j.get("path") or "").strip()
                    if _rl_is_rid(rid) and pth and Path(pth).is_dir():
                        ok, why = _rl_has_core_artifacts(Path(pth))
                        if ok:
                            return jsonify({"ok": True, "rid": rid, "path": pth, "mtime": j.get("mtime",0), "stale": True,
                                            "candidates": 0, "checked": 0, "why": why})
            except Exception:
                pass

            return jsonify({"ok": False, "rid": "", "stale": False, "candidates": total, "checked": checked,
                            "err": "no run dir with required artifacts found"})

        # Force-bind by url_map (override previous rid_latest handler)
        eps=[]
        try:
            for rule in list(_app.url_map.iter_rules()):
                if getattr(rule, "rule", "") == "/api/vsp/rid_latest" and ("GET" in (rule.methods or set())):
                    eps.append(rule.endpoint)
        except Exception as e:
            print("[{MARK}] WARN url_map scan failed:", repr(e))

        if eps:
            for ep in eps:
                _app.view_functions[ep] = vsp_rid_latest_prefer_has_findings_v1
            print("[{MARK}] OK rebound existing endpoints:", eps)
        else:
            _app.add_url_rule("/api/vsp/rid_latest", "vsp_rid_latest_prefer_has_findings_v1",
                              vsp_rid_latest_prefer_has_findings_v1, methods=["GET"])
            print("[{MARK}] OK added new rule endpoint=vsp_rid_latest_prefer_has_findings_v1")

except Exception as _e:
    print("[{MARK}] FAILED:", repr(_e))
# ===================== /{MARK} =====================
""").replace("{MARK}", MARK).strip()+"\n"

m=re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m:
    s = s[:m.start()] + block + "\n" + s[m.start():]
else:
    s = s.rstrip() + "\n\n" + block

p.write_text(s, encoding="utf-8")
print("[OK] appended", MARK, "into", p)
PY

# compile; rollback if fail
if ! python3 -m py_compile "$PYF" >/dev/null 2>&1; then
  echo "[ERR] py_compile failed => rollback to $BAK"
  cp -f "$BAK" "$PYF"
  python3 -m py_compile "$PYF" >/dev/null 2>&1 || true
  exit 3
fi
echo "[OK] py_compile: $PYF"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] rid_latest now prefers runs that actually have findings/run_gate artifacts."
