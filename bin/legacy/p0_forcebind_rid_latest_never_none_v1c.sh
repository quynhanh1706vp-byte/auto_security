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

cp -f "$PYF" "${PYF}.bak_ridlatest_forcebind_${TS}"
echo "[BACKUP] ${PYF}.bak_ridlatest_forcebind_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RID_LATEST_NEVER_NONE_FORCEBIND_V1C"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

block=textwrap.dedent(rf"""
# ===================== {MARK} =====================
try:
    import json, time, re
    from pathlib import Path
    from flask import jsonify

    _app = globals().get("app") or globals().get("application")
    if _app is None:
        print("[{MARK}] WARN: cannot find app/application in globals()")
    else:
        def _vsp_is_rid(v: str) -> bool:
            if not v: return False
            v = str(v).strip()
            if len(v) < 6 or len(v) > 120: return False
            if any(c.isspace() for c in v): return False
            if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.:-]+$", v): return False
            if not any(ch.isdigit() for ch in v): return False
            return True

        def _vsp_pick_latest_rid():
            roots = [
                Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
                Path("/home/test/Data/SECURITY_BUNDLE/out"),
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
            ]
            base = Path("/home/test/Data")
            if base.is_dir():
                try:
                    for d in base.iterdir():
                        if d.is_dir() and d.name.startswith("SECURITY"):
                            roots.append(d/"out_ci")
                            roots.append(d/"out")
                except Exception:
                    pass

            cand=[]
            def consider_dir(x: Path):
                try:
                    if not x.is_dir(): return
                    rid=x.name
                    if not _vsp_is_rid(rid): return
                    if not (rid.startswith("RUN_") or "VSP" in rid or "_RUN_" in rid):
                        return
                    cand.append((x.stat().st_mtime, rid, str(x)))
                except Exception:
                    return

            for r in roots:
                try:
                    if not r.is_dir(): continue
                    for x in r.iterdir():
                        consider_dir(x)
                except Exception:
                    continue

            cand.sort(reverse=True, key=lambda t: t[0])
            return cand[0] if cand else None, len(cand)

        def vsp_rid_latest_never_none_v1c():
            """
            Commercial-safe: never 500, never rid=None.
            - pick newest RID by mtime from known roots
            - fallback to cached last-good
            """
            cache_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/_rid_latest_cache.json")
            cache_path.parent.mkdir(parents=True, exist_ok=True)

            best, n = _vsp_pick_latest_rid()
            if best:
                mt, rid, pth = best
                try:
                    cache_path.write_text(json.dumps({"rid": rid, "path": pth, "mtime": mt, "ts": time.time()}, ensure_ascii=False),
                                          encoding="utf-8")
                except Exception:
                    pass
                return jsonify({"ok": True, "rid": rid, "path": pth, "mtime": mt, "stale": False, "candidates": n})

            # fallback cache
            try:
                if cache_path.is_file():
                    j=json.loads(cache_path.read_text(encoding="utf-8", errors="replace") or "{}")
                    rid=(j.get("rid") or "").strip()
                    if _vsp_is_rid(rid):
                        return jsonify({"ok": True, "rid": rid, "path": j.get("path",""), "mtime": j.get("mtime",0),
                                        "stale": True, "candidates": 0})
            except Exception:
                pass

            # never rid=None
            return jsonify({"ok": False, "rid": "", "stale": False, "candidates": 0, "err": "no run dir found"})

        # Force-bind by url_map (works even if original was endwrapped/middleware)
        eps=[]
        try:
            for rule in list(_app.url_map.iter_rules()):
                if getattr(rule, "rule", "") == "/api/vsp/rid_latest" and ("GET" in (rule.methods or set())):
                    eps.append(rule.endpoint)
        except Exception as e:
            print(f"[{MARK}] WARN url_map scan failed:", repr(e))

        if eps:
            for ep in eps:
                _app.view_functions[ep] = vsp_rid_latest_never_none_v1c
            print(f"[{MARK}] OK rebound existing endpoints:", eps)
        else:
            # no rule? add it
            _app.add_url_rule("/api/vsp/rid_latest", "vsp_rid_latest_never_none_v1c", vsp_rid_latest_never_none_v1c, methods=["GET"])
            print(f"[{MARK}] OK added new rule endpoint=vsp_rid_latest_never_none_v1c")

except Exception as _e:
    print("[{MARK}] FAILED:", repr(_e))
# ===================== /{MARK} =====================
""").strip()+"\n"

# insert before if __name__ == "__main__" if present, else append EOF
m=re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m:
    s = s[:m.start()] + block + "\n" + s[m.start():]
else:
    s = s.rstrip() + "\n\n" + block

p.write_text(s, encoding="utf-8")
print("[OK] appended", MARK, "into", p)
PY

python3 -m py_compile "$PYF" && echo "[OK] py_compile: $PYF" || { echo "[ERR] py_compile failed"; exit 3; }

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Force-bound /api/vsp/rid_latest. Now verify with curl."
