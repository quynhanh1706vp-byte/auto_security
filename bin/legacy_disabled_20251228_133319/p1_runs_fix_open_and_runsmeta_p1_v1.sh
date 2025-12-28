#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

TS="$(date +%Y%m%d_%H%M%S)"
FILES=()
[ -f wsgi_vsp_ui_gateway.py ] && FILES+=(wsgi_vsp_ui_gateway.py)
[ -f vsp_demo_app.py ] && FILES+=(vsp_demo_app.py)
[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] missing both wsgi_vsp_ui_gateway.py and vsp_demo_app.py"; exit 2; }

for f in "${FILES[@]}"; do
  cp -f "$f" "${f}.bak_runsmeta_${TS}"
  echo "[BACKUP] ${f}.bak_runsmeta_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import textwrap, json, os, re

marker = "VSP_P1_RUNS_OPEN_AND_META_P1_V1"

def patch_file(fn: str):
    p = Path(fn)
    s = p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[SKIP] marker already in", fn)
        return

    block = textwrap.dedent(f"""
    # --- {marker} ---
    # Goals:
    # 1) Ensure /api/vsp/open* exists to stop 404 spam from Runs tab (SAFE default: no xdg-open).
    # 2) Enrich /api/vsp/runs output with per-item has_gate/overall/degraded + rid_latest_gate.
    try:
        from flask import request, jsonify
        import os as _os
        import json as _json
        from pathlib import Path as _Path
        import subprocess as _subprocess
    except Exception:
        request = None
        jsonify = None

    def _vsp_find_run_dir(_rid: str, roots):
        if not _rid:
            return None
        for r in roots or []:
            if not r:
                continue
            base = _Path(r)
            cand = base / _rid
            if cand.exists():
                return str(cand.resolve())
        return None

    def _vsp_gate_candidates():
        return [
            "run_gate_summary.json",
            "reports/run_gate_summary.json",
            "run_gate.json",
            "reports/run_gate.json",
        ]

    def _vsp_try_read_json(path: str, max_bytes=2_000_000):
        try:
            pp = _Path(path)
            if not pp.exists() or not pp.is_file():
                return None
            if pp.stat().st_size > max_bytes:
                return None
            return _json.loads(pp.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            return None

    def _vsp_extract_overall_degraded(obj):
        overall = None
        degraded = None
        if isinstance(obj, dict):
            overall = obj.get("overall") or obj.get("overall_status") or obj.get("status")
            if isinstance(obj.get("degraded"), bool):
                degraded = obj.get("degraded")
            # scan by_type.*.degraded if present
            bt = obj.get("by_type")
            if degraded is None and isinstance(bt, dict):
                for v in bt.values():
                    if isinstance(v, dict) and v.get("degraded") is True:
                        degraded = True
                        break
        if not overall:
            overall = "UNKNOWN"
        if degraded is None:
            degraded = False
        return overall, degraded

    def _vsp_open_payload(rid: str, what: str, roots):
        run_dir = _vsp_find_run_dir(rid, roots)
        allow = _os.environ.get("VSP_UI_ALLOW_XDG_OPEN", "0") == "1"
        opened = False
        err = None
        if allow and run_dir and what in ("folder","dir","run_dir"):
            try:
                _subprocess.Popen(["xdg-open", run_dir],
                                  stdout=_subprocess.DEVNULL, stderr=_subprocess.DEVNULL)
                opened = True
            except Exception as e:
                err = str(e)
        payload = {{
            "ok": True,
            "rid": rid,
            "what": what,
            "run_dir": run_dir,
            "opened": opened,
            "disabled": (not allow),
            "hint": "SAFE default: opener disabled. Set VSP_UI_ALLOW_XDG_OPEN=1 to enable (dev only)."
        }}
        if err:
            payload["error"] = err
        return payload

    def _vsp_post_mount_fixups():
        app = globals().get("app") or globals().get("application")
        if app is None or request is None or jsonify is None:
            return

        # ---- ensure /api/vsp/open exists (no 404) ----
        rules = list(app.url_map.iter_rules())
        has_open = any(r.rule == "/api/vsp/open" for r in rules)
        has_open_folder = any(r.rule == "/api/vsp/open_folder" for r in rules)

        def _roots_from_env_or_resp(resp_json=None):
            roots = []
            # prefer server-known roots, else common defaults
            roots += [os.environ.get("VSP_RUNS_ROOT","")]
            roots += ["/home/test/Data/SECURITY_BUNDLE/out", "/home/test/Data/SECURITY_BUNDLE/out_ci"]
            if isinstance(resp_json, dict):
                ru = resp_json.get("roots_used")
                if isinstance(ru, list):
                    roots = ru + roots
            # dedupe keep order
            out = []
            for r in roots:
                if r and r not in out:
                    out.append(r)
            return out

        if not has_open:
            def vsp_open_p1_v1():
                rid = (request.args.get("rid","") or "").strip()
                what = (request.args.get("what","folder") or "folder").strip()
                roots = _roots_from_env_or_resp(None)
                return jsonify(_vsp_open_payload(rid, what, roots))
            app.add_url_rule("/api/vsp/open", endpoint="vsp_open_p1_v1", view_func=vsp_open_p1_v1, methods=["GET"])

        if not has_open_folder:
            def vsp_open_folder_p1_v1():
                rid = (request.args.get("rid","") or "").strip()
                roots = _roots_from_env_or_resp(None)
                return jsonify(_vsp_open_payload(rid, "folder", roots))
            app.add_url_rule("/api/vsp/open_folder", endpoint="vsp_open_folder_p1_v1", view_func=vsp_open_folder_p1_v1, methods=["GET"])

        # ---- wrap /api/vsp/runs to add has_gate/overall/degraded ----
        for r in app.url_map.iter_rules():
            if r.rule != "/api/vsp/runs":
                continue
            ep = r.endpoint
            orig = app.view_functions.get(ep)
            if not orig or getattr(orig, "__vsp_wrapped_runsmeta", False):
                continue

            def _wrap(orig_func):
                def wrapped(*args, **kwargs):
                    resp = orig_func(*args, **kwargs)
                    status = None
                    headers = None
                    resp_obj = resp
                    if isinstance(resp, tuple) and len(resp) >= 1:
                        resp_obj = resp[0]
                        if len(resp) >= 2: status = resp[1]
                        if len(resp) >= 3: headers = resp[2]

                    data = None
                    if hasattr(resp_obj, "get_json"):
                        data = resp_obj.get_json(silent=True)
                    elif isinstance(resp_obj, dict):
                        data = resp_obj

                    if isinstance(data, dict) and isinstance(data.get("items"), list):
                        roots = _roots_from_env_or_resp(data)
                        rid_latest_gate = None

                        for it in data["items"]:
                            rid = it.get("run_id") if isinstance(it, dict) else None
                            run_dir = _vsp_find_run_dir(rid, roots) if rid else None

                            has_gate = False
                            overall = "UNKNOWN"
                            degraded = False

                            if run_dir:
                                for rel in _vsp_gate_candidates():
                                    fp = str(_Path(run_dir) / rel)
                                    obj = _vsp_try_read_json(fp)
                                    if isinstance(obj, dict):
                                        has_gate = True
                                        overall, degraded = _vsp_extract_overall_degraded(obj)
                                        break

                            # enrich
                            if isinstance(it, dict):
                                it.setdefault("has", {})
                                it["has"]["gate"] = bool(has_gate)
                                it["overall"] = overall
                                it["degraded"] = bool(degraded)

                            if rid_latest_gate is None and has_gate:
                                rid_latest_gate = rid

                        data["rid_latest_gate"] = rid_latest_gate
                        # optional: keep compatibility but prefer gate if exists
                        if rid_latest_gate:
                            data["rid_latest"] = rid_latest_gate

                        new_resp = jsonify(data)
                        if headers:
                            for k, v in headers.items() if hasattr(headers, "items") else []:
                                new_resp.headers[k] = v
                        if status is not None:
                            return new_resp, status
                        return new_resp

                    return resp
                wrapped.__vsp_wrapped_runsmeta = True
                return wrapped

            app.view_functions[ep] = _wrap(orig)
            break

    try:
        _vsp_post_mount_fixups()
    except Exception:
        pass
    """).strip() + "\n"

    p.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
    print("[OK] appended", marker, "to", fn)

for fn in ["wsgi_vsp_ui_gateway.py", "vsp_demo_app.py"]:
    if Path(fn).exists():
        patch_file(fn)
PY

# compile check
for f in "${FILES[@]}"; do
  python3 -m py_compile "$f"
done
echo "[OK] py_compile OK"

echo "== RESTART REQUIRED =="
echo "sudo systemctl restart vsp-ui-8910.service  # if you use systemd"
echo "or run your existing start script for :8910"

echo "== AFTER restart, verify =="
echo "curl -sS http://127.0.0.1:8910/api/vsp/open | head -c 200; echo"
echo "curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=2 | head -c 900; echo"
