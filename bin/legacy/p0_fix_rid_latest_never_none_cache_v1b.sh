#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

# Find python file that owns rid_latest route
TARGET="$(python3 - <<'PY'
from pathlib import Path
root=Path(".")
cands=[]
for p in root.rglob("*.py"):
    if any(x in p.parts for x in ("out_ci","bin","static",".venv","node_modules","__pycache__")):
        continue
    try:
        t=p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "/api/vsp/rid_latest" in t or "rid_latest" in t:
        cands.append(str(p))
print(cands[0] if cands else "")
PY
)"
[ -n "$TARGET" ] || { echo "[ERR] cannot find rid_latest route in *.py"; exit 2; }
echo "[INFO] patch target: $TARGET"

cp -f "$TARGET" "${TARGET}.bak_ridlatest_${TS}"
echo "[BACKUP] ${TARGET}.bak_ridlatest_${TS}"

export TARGET

python3 - <<'PY'
import os, re, textwrap
from pathlib import Path

target = Path(os.environ["TARGET"])
s = target.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RID_LATEST_NEVER_NONE_CACHE_V1B"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# match @app.route("/api/vsp/rid_latest"...)/@app.get("/api/vsp/rid_latest"...)
pat = re.compile(
    r"(?ms)@app\.(?:route|get)\(\s*['\"]\/api\/vsp\/rid_latest['\"].*?\)\s*\n"
    r"\s*def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*?\)\s*:\s*\n"
    r"(.*?)(?=\n@app\.(?:route|get|post|put|delete)\(|\nif\s+__name__\s*==\s*['\"]__main__['\"]|\Z)"
)
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find rid_latest function block to replace")

func_name = m.group(1) or "rid_latest"

replacement = textwrap.dedent(f"""
@app.route("/api/vsp/rid_latest", methods=["GET"])
def {func_name}():
    \"\"\"{MARK}
    Commercial-safe: never 500, never rid=None.
    - scan multiple roots for run directories (VSP_CI_* / RUN_* / *_RUN_*)
    - pick newest by mtime
    - cache last-good RID to ui/out_ci/_rid_latest_cache.json
    - if scan fails, return cached rid (stale=true)
    \"\"\"
    try:
        import json, time, re
        from pathlib import Path

        def _is_rid(v: str) -> bool:
            if not v: return False
            v = str(v).strip()
            if len(v) < 6 or len(v) > 120: return False
            if any(c.isspace() for c in v): return False
            if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.:-]+$", v): return False
            if not any(ch.isdigit() for ch in v): return False
            return True

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
                        roots.append(d / "out_ci")
                        roots.append(d / "out")
            except Exception:
                pass

        cand = []  # (mtime, rid, path)
        def consider_dir(p: Path):
            try:
                if not p.is_dir(): return
                rid = p.name
                if not _is_rid(rid): return
                if not (rid.startswith("RUN_") or "VSP" in rid or "_RUN_" in rid):
                    return
                mt = p.stat().st_mtime
                cand.append((mt, rid, str(p)))
            except Exception:
                return

        for r in roots:
            try:
                if not r.is_dir():
                    continue
                for x in r.iterdir():
                    consider_dir(x)
            except Exception:
                continue

        cand.sort(reverse=True, key=lambda t: t[0])
        best = cand[0] if cand else None

        cache_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/_rid_latest_cache.json")
        cache_path.parent.mkdir(parents=True, exist_ok=True)

        if best:
            mt, rid, pth = best
            try:
                cache_path.write_text(json.dumps({{"rid": rid, "path": pth, "mtime": mt, "ts": time.time()}}, ensure_ascii=False), encoding="utf-8")
            except Exception:
                pass
            return jsonify({{"ok": True, "rid": rid, "path": pth, "mtime": mt, "stale": False, "candidates": len(cand)}})

        # fallback to cache
        try:
            if cache_path.is_file():
                j = json.loads(cache_path.read_text(encoding="utf-8", errors="replace") or "{{}}")
                rid = (j.get("rid") or "").strip()
                if _is_rid(rid):
                    return jsonify({{"ok": True, "rid": rid, "path": j.get("path",""), "mtime": j.get("mtime",0), "stale": True, "candidates": 0}})
        except Exception:
            pass

        # never return None/500
        return jsonify({{"ok": False, "rid": "", "stale": False, "candidates": 0, "err": "no run dir found"}})

    except Exception as e:
        return jsonify({{"ok": False, "rid": "", "stale": False, "candidates": 0, "err": str(e)[:180]}})
""").strip() + "\n"

new_s = s[:m.start()] + replacement + s[m.end():]
target.write_text(new_s, encoding="utf-8")
print("[OK] patched rid_latest in", target, "marker:", MARK)
PY

python3 -m py_compile "$TARGET" && echo "[OK] py_compile: $TARGET" || { echo "[ERR] py_compile failed"; exit 3; }

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] rid_latest is commercial-safe now. Hard refresh /vsp5."
