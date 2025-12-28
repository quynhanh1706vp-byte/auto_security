#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_rule_overrides_wsgi_${TS}"
echo "[BACKUP] ${F}.bak_rule_overrides_wsgi_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RULE_OVERRIDES_APPLY_WSGI_INTERCEPT_V1"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

BLOCK = textwrap.dedent(f'''
# ===================== {MARK} =====================
# Commercial hardening: WSGI intercept so /api/ui/rule_overrides_v2_apply_v2 never 404,
# always returns HTTP 200 JSON, and never crashes the 8910 process.

def _vsp_ro_json(start_response, payload: dict):
    import json
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Cache-Control", "no-store"),
        ("Pragma", "no-cache"),
        ("Expires", "0"),
        ("Content-Length", str(len(body))),
    ]
    start_response("200 OK", headers)
    return [body]

def _vsp_ro_read_body(environ, limit=262144):
    try:
        wsgi_input = environ.get("wsgi.input")
        if not wsgi_input:
            return b""
        try:
            clen = int(environ.get("CONTENT_LENGTH") or "0")
        except Exception:
            clen = 0
        # read bounded
        n = clen if 0 < clen <= limit else limit
        return wsgi_input.read(n) if n > 0 else b""
    except Exception:
        return b""

def _vsp_ro_guess_run_dir(rid: str):
    import os
    from pathlib import Path
    roots = []
    env_root = os.environ.get("VSP_OUT_ROOT") or os.environ.get("SECURITY_BUNDLE_OUT_ROOT")
    if env_root:
        roots.append(env_root)
    roots += [
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out_ci/ui",  # harmless
    ]
    # direct
    for r in roots:
        pr = Path(r)
        cand = pr / rid
        if cand.is_dir():
            return cand
    # common nested layout: out/RUN_*/...
    for r in roots:
        pr = Path(r)
        if not pr.is_dir():
            continue
        # 1) exact match under one level
        cand = pr / rid
        if cand.is_dir():
            return cand
        # 2) fuzzy prefix
        cands = sorted(pr.glob(f"{rid}*"), key=lambda x: x.stat().st_mtime if x.exists() else 0, reverse=True)
        for c in cands:
            if c.is_dir():
                return c
        # 3) deep search (bounded)
        try:
            deep = sorted(pr.glob(f"**/{rid}"), key=lambda x: x.stat().st_mtime if x.exists() else 0, reverse=True)
            for d in deep[:5]:
                if d.is_dir():
                    return d
        except Exception:
            pass
    return None

def _vsp_ro_store_path():
    import os
    from pathlib import Path
    base = os.environ.get("VSP_RULE_OVERRIDES_DIR") or "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2"
    bd = Path(base)
    bd.mkdir(parents=True, exist_ok=True)
    return bd / "rule_overrides.json"

def _vsp_ro_read_overrides():
    import json
    f = _vsp_ro_store_path()
    if not f.exists():
        f.write_text(json.dumps({{"version": 2, "rules": []}}, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        return json.loads(f.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return {{"version": 2, "rules": [], "_corrupted": True}}

def _vsp_ro_write_marker(run_dir, rid: str, overrides: dict, status: str, note: str):
    import json, time
    from pathlib import Path
    rd = Path(str(run_dir))
    payload = {{
        "rid": rid,
        "applied_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "status": status,
        "note": note,
        "overrides_meta": {{
            "store": str(_vsp_ro_store_path()),
            "version": overrides.get("version"),
            "rules_count": len(overrides.get("rules") or []),
            "corrupted": bool(overrides.get("_corrupted", False)),
        }}
    }}
    try:
        (rd / "reports").mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    for out in [rd/"rule_overrides_applied.json", rd/"reports"/"rule_overrides_applied.json"]:
        try:
            out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            pass
    return payload

class _VSPRuleOverridesApplyWSGI:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        import time, json, traceback
        path = environ.get("PATH_INFO") or ""
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        if path == "/api/ui/rule_overrides_v2_apply_v2" and method == "POST":
            try:
                raw = _vsp_ro_read_body(environ)
                try:
                    body = json.loads(raw.decode("utf-8", errors="replace") or "{{}}")
                except Exception:
                    body = {{}}

                rid = (body.get("rid") or "").strip()
                if not rid:
                    return _vsp_ro_json(start_response, {{
                        "ok": False, "degraded": True, "error": "missing_rid", "path": path, "ts": int(time.time())
                    }})

                overrides = _vsp_ro_read_overrides()
                run_dir = _vsp_ro_guess_run_dir(rid)

                if run_dir is None:
                    return _vsp_ro_json(start_response, {{
                        "ok": False, "degraded": True, "rid": rid,
                        "error": "run_dir_not_found",
                        "overrides_meta": {{
                            "store": str(_vsp_ro_store_path()),
                            "version": overrides.get("version"),
                            "rules_count": len(overrides.get("rules") or []),
                            "corrupted": bool(overrides.get("_corrupted", False)),
                        }},
                        "path": path, "ts": int(time.time())
                    }})

                marker = _vsp_ro_write_marker(run_dir, rid, overrides, status="OK", note="marker_written_only")
                return _vsp_ro_json(start_response, {{
                    "ok": True, "degraded": False, "rid": rid,
                    "run_dir": str(run_dir),
                    "mode": "MARKER_ONLY",
                    "marker": marker,
                    "path": path, "ts": int(time.time())
                }})
            except Exception as e:
                return _vsp_ro_json(start_response, {{
                    "ok": False, "degraded": True, "error": str(e),
                    "trace": traceback.format_exc()[-1600:],
                    "path": path, "ts": int(time.time())
                }})

        # pass-through
        return self.app(environ, start_response)

# Wrap the exported WSGI application safely (works even if app routes are registered later)
try:
    application  # noqa
except Exception:
    try:
        application = app  # type: ignore
    except Exception:
        application = None

if application is not None:
    # avoid double wrap
    if not getattr(application, "_vsp_ro_wsgi_wrapped", False):
        _wrapped = _VSPRuleOverridesApplyWSGI(application)
        setattr(_wrapped, "_vsp_ro_wsgi_wrapped", True)
        application = _wrapped
# ===================== /{MARK} =====================
''').strip("\n")

# Append block near end (before __main__ if exists)
ins = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
if ins:
    s2 = s[:ins.start()] + "\n\n" + BLOCK + "\n\n" + s[ins.start():]
else:
    s2 = s + "\n\n" + BLOCK + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "[DONE] Restart UI now:"
echo "  rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.*; bin/p1_ui_8910_single_owner_start_v2.sh"
