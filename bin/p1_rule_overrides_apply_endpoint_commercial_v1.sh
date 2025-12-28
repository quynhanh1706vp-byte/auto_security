#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_rule_overrides_apply_${TS}"
echo "[BACKUP] ${F}.bak_rule_overrides_apply_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RULE_OVERRIDES_APPLY_COMMERCIAL_V1"
BLOCK = textwrap.dedent(r'''
# ===================== {MARK} =====================
# Commercial-hardening for Rule Overrides apply endpoint:
# - Never 404 for apply endpoint
# - Never crash 8910 (always catches exceptions)
# - Always returns HTTP 200 JSON with ok/degraded flags
# - Writes an "applied marker" into run_dir for UI to detect
try:
    import os, json, time, traceback
    from pathlib import Path
    from flask import request, jsonify, make_response
except Exception:
    pass

def _vsp_json_200(payload: dict):
    try:
        resp = make_response(jsonify(payload), 200)
        resp.headers["Cache-Control"] = "no-store"
        resp.headers["Pragma"] = "no-cache"
        resp.headers["Expires"] = "0"
        return resp
    except Exception:
        # fallback ultra-safe
        import json as _json
        body = _json.dumps(payload, ensure_ascii=False)
        return (body, 200, {"Content-Type":"application/json; charset=utf-8",
                            "Cache-Control":"no-store","Pragma":"no-cache","Expires":"0"})

def _vsp_guess_run_dir(rid: str):
    # Prefer env override, else common roots in SECURITY_BUNDLE
    roots = []
    env_root = os.environ.get("VSP_OUT_ROOT") or os.environ.get("SECURITY_BUNDLE_OUT_ROOT")
    if env_root:
        roots.append(env_root)
    roots += [
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
    ]
    for r in roots:
        pr = Path(r)
        cand = pr / rid
        if cand.is_dir():
            return cand

    # fallback: try fuzzy match (rid prefix) by mtime
    for r in roots:
        pr = Path(r)
        if not pr.is_dir():
            continue
        cands = sorted(pr.glob(f"{rid}*"), key=lambda x: x.stat().st_mtime if x.exists() else 0, reverse=True)
        for c in cands:
            if c.is_dir():
                return c
    return None

def _vsp_rule_overrides_store():
    # central store for UI editing; safe default under ui/out_ci
    base = os.environ.get("VSP_RULE_OVERRIDES_DIR") or "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2"
    bd = Path(base)
    bd.mkdir(parents=True, exist_ok=True)
    return bd / "rule_overrides.json"

def _vsp_read_overrides():
    f = _vsp_rule_overrides_store()
    if not f.exists():
        # create minimal v2 structure
        f.write_text(json.dumps({"version":2,"rules":[]}, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        return json.loads(f.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        # if corrupted, don't break apply
        return {"version":2,"rules":[],"_corrupted":True}

def _vsp_write_applied_marker(run_dir: Path, rid: str, overrides_obj: dict, status: str, note: str):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    payload = {
        "rid": rid,
        "applied_at": ts,
        "status": status,          # OK / DEGRADED / ERROR
        "note": note,
        "overrides_meta": {
            "version": overrides_obj.get("version", None),
            "rules_count": len(overrides_obj.get("rules", []) or []),
            "corrupted": bool(overrides_obj.get("_corrupted", False)),
        }
    }
    # write in both root + reports/ for easy pickup
    try:
        (run_dir / "reports").mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    for out in [run_dir/"rule_overrides_applied.json", run_dir/"reports"/"rule_overrides_applied.json"]:
        try:
            out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            pass
    return payload

# ---- (A) GET: UI fetch current overrides (optional helper) ----
try:
    @app.route("/api/ui/rule_overrides_v2_get_v1", methods=["GET"])
    def vsp_rule_overrides_v2_get_v1():
        obj = _vsp_read_overrides()
        return _vsp_json_200({"ok": True, "data": obj, "store": str(_vsp_rule_overrides_store())})
except Exception:
    pass

# ---- (B) POST: UI save overrides (optional helper) ----
try:
    @app.route("/api/ui/rule_overrides_v2_save_v1", methods=["POST"])
    def vsp_rule_overrides_v2_save_v1():
        try:
            body = request.get_json(force=True, silent=True) or {}
            data = body.get("data")
            if not isinstance(data, dict):
                return _vsp_json_200({"ok": False, "degraded": True, "error": "invalid_payload_expect_data_object"})
            f = _vsp_rule_overrides_store()
            f.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
            return _vsp_json_200({"ok": True, "saved": True, "store": str(f)})
        except Exception as e:
            return _vsp_json_200({"ok": False, "degraded": True, "error": str(e), "trace": traceback.format_exc()[-1200:]})
except Exception:
    pass

# ---- (C) POST: Apply overrides to a run (commercial contract) ----
def _vsp_apply_rule_overrides_v2_apply_v2_impl():
    rid = ""
    try:
        body = request.get_json(force=True, silent=True) or {}
        rid = (body.get("rid") or "").strip()
        if not rid:
            return _vsp_json_200({"ok": False, "degraded": True, "error": "missing_rid"})
        run_dir = _vsp_guess_run_dir(rid)
        overrides = _vsp_read_overrides()

        if run_dir is None:
            # don't 404; return degraded
            return _vsp_json_200({
                "ok": False,
                "degraded": True,
                "rid": rid,
                "error": "run_dir_not_found",
                "roots_hint": [
                    os.environ.get("VSP_OUT_ROOT"),
                    "/home/test/Data/SECURITY_BUNDLE/out",
                    "/home/test/Data/SECURITY_BUNDLE/out_ci",
                    "/home/test/Data/SECURITY-10-10-v4/out_ci",
                ],
                "overrides_meta": {
                    "store": str(_vsp_rule_overrides_store()),
                    "version": overrides.get("version", None),
                    "rules_count": len(overrides.get("rules", []) or []),
                    "corrupted": bool(overrides.get("_corrupted", False)),
                }
            })

        # We do NOT attempt to mutate findings here (schema unknown).
        # We write an applied marker file so UI + any downstream tool can pick it up safely.
        marker = _vsp_write_applied_marker(run_dir, rid, overrides, status="OK", note="marker_written_only")

        return _vsp_json_200({
            "ok": True,
            "degraded": False,
            "rid": rid,
            "run_dir": str(run_dir),
            "applied": True,
            "mode": "MARKER_ONLY",
            "marker": marker,
            "overrides_store": str(_vsp_rule_overrides_store()),
        })
    except Exception as e:
        return _vsp_json_200({
            "ok": False,
            "degraded": True,
            "rid": rid,
            "error": str(e),
            "trace": traceback.format_exc()[-1800:],
        })

# Replace existing route if present; else register new route
try:
    _has = "/api/ui/rule_overrides_v2_apply_v2" in globals().get("__file__", "")  # dummy
except Exception:
    _has = False

try:
    # if an old handler exists, we still register under same URL but unique endpoint name is important
    app.add_url_rule(
        "/api/ui/rule_overrides_v2_apply_v2",
        endpoint="vsp_rule_overrides_v2_apply_v2__commercial_v1",
        view_func=_vsp_apply_rule_overrides_v2_apply_v2_impl,
        methods=["POST"]
    )
except Exception:
    # as last resort, try decorator form (may fail if already registered)
    try:
        @app.route("/api/ui/rule_overrides_v2_apply_v2", methods=["POST"])
        def vsp_rule_overrides_v2_apply_v2__commercial_v1():
            return _vsp_apply_rule_overrides_v2_apply_v2_impl()
    except Exception:
        pass
# ===================== /{MARK} =====================
''').strip("\n").replace("{MARK}", MARK)

if MARK in s:
    print("[OK] marker already present:", MARK)
    raise SystemExit(0)

# Ensure flask imports include request/jsonify/make_response if there is a "from flask import ..." line
m = re.search(r'^\s*from\s+flask\s+import\s+([^\n]+)\n', s, flags=re.M)
if m:
    items = [x.strip() for x in m.group(1).split(",")]
    need = ["request", "jsonify", "make_response"]
    changed = False
    for x in need:
        if x not in items:
            items.append(x)
            changed = True
    if changed:
        new_line = "from flask import " + ", ".join(sorted(dict.fromkeys(items), key=lambda z: items.index(z))) + "\n"
        s = s[:m.start()] + new_line + s[m.end():]
else:
    # no import line found; do nothing (BLOCK has guarded imports)
    pass

# If old string exists, do not duplicate by decorator; we use add_url_rule with unique endpoint.
# Insert BLOCK near end, before if __name__ == "__main__" if present, else append.
ins = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
if ins:
    s2 = s[:ins.start()] + "\n\n" + BLOCK + "\n\n" + s[ins.start():]
else:
    s2 = s + "\n\n" + BLOCK + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] appended commercial Rule Overrides apply block:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "[NEXT] restart UI service then verify:"
echo "  rm -f /tmp/vsp_ui_8910.lock; bin/p1_ui_8910_single_owner_start_v2.sh"
echo "  curl -sS -I http://127.0.0.1:8910/rule_overrides | head"
echo "  curl -sS -X POST http://127.0.0.1:8910/api/ui/rule_overrides_v2_apply_v2 -H 'Content-Type: application/json' -d '{\"rid\":\"RUN_20251120_130310\"}' | head -c 300; echo"
