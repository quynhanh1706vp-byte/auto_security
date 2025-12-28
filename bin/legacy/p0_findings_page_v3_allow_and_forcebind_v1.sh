#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P0_FINDINGS_PAGE_V3_ALLOW_FORCEBIND_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_findingsv3_${TS}"
echo "[BACKUP] ${W}.bak_findingsv3_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P0_FINDINGS_PAGE_V3_ALLOW_FORCEBIND_V1"
if mark in s:
    print("[SKIP] marker already present")
else:
    block = textwrap.dedent(r'''
    # ===================== VSP_P0_FINDINGS_PAGE_V3_ALLOW_FORCEBIND_V1 =====================
    # Purpose:
    #  - Ensure /api/vsp/findings_page is NOT blocked by outer allowlist guard ("not allowed")
    #  - Provide commercial-grade findings pagination API (bounded, cached, safe defaults)
    try:
        import os, json, time
        from pathlib import Path
        try:
            from flask import request, jsonify
        except Exception:
            request = None
            jsonify = None

        _VSP_FINDINGS_PAGE_PATH = "/api/vsp/findings_page"

        def _vsp__patch_allowlists_for_findings_page() -> bool:
            """
            Best-effort: find global allowlist containers that already allow /api/vsp/runs + /api/vsp/release_latest
            and append/add /api/vsp/findings_page.
            This fixes: {"ok":false,"err":"not allowed","path":"/api/vsp/findings_page"}.
            """
            added = False
            try:
                g = globals()
                needle_a = "/api/vsp/runs"
                needle_b = "/api/vsp/release_latest"
                for k, v in list(g.items()):
                    if isinstance(v, (set, list, tuple)) and (needle_a in v) and (needle_b in v):
                        if _VSP_FINDINGS_PAGE_PATH in v:
                            continue
                        try:
                            # set
                            v.add(_VSP_FINDINGS_PAGE_PATH)  # type: ignore[attr-defined]
                            added = True
                        except Exception:
                            try:
                                # list
                                v = list(v) + [_VSP_FINDINGS_PAGE_PATH]
                                g[k] = v
                                added = True
                            except Exception:
                                pass
                # also patch dict-of-bools allow tables if any
                for k, v in list(g.items()):
                    if isinstance(v, dict) and (needle_a in v) and (needle_b in v):
                        if _VSP_FINDINGS_PAGE_PATH not in v:
                            try:
                                v[_VSP_FINDINGS_PAGE_PATH] = True
                                added = True
                            except Exception:
                                pass
            except Exception:
                pass
            return added

        _VSP_FP_CACHE = {
            "rid": None,
            "run_dir": None,
            "fp": None,
            "mtime": 0.0,
            "total": 0,
            "meta": None,
            "findings": None,
            "ts": 0.0,
        }

        def _vsp__pick_flask_app():
            g = globals()
            # common names first
            for name in ("app", "flask_app", "vsp_app"):
                obj = g.get(name)
                if obj is not None and hasattr(obj, "add_url_rule") and hasattr(obj, "url_map"):
                    return obj
            # scan any global object that looks like Flask
            for obj in g.values():
                if obj is not None and hasattr(obj, "add_url_rule") and hasattr(obj, "url_map") and hasattr(obj, "view_functions"):
                    return obj
            return None

        def _vsp__bounded_find_run_dir(rid: str):
            # accept absolute dir
            if rid and rid.startswith("/") and Path(rid).is_dir():
                return rid
            rid = (rid or "").strip()
            if not rid:
                return None

            # roots: keep aligned with your ecosystem (SECURITY_BUNDLE + legacy out_ci)
            roots = []
            roots += [os.environ.get("VSP_OUT_CI", "").strip()] if os.environ.get("VSP_OUT_CI") else []
            roots += [
                "/home/test/Data/SECURITY-10-10-v4/out_ci",
                "/home/test/Data/SECURITY_BUNDLE/out_ci",
                "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
                "/home/test/Data/SECURITY_BUNDLE/out",
            ]
            # de-dup keep order
            seen = set()
            roots2 = []
            for r in roots:
                r = (r or "").strip()
                if not r or r in seen:
                    continue
                seen.add(r)
                roots2.append(r)
            roots = roots2

            # fast direct hit
            for r in roots:
                cand = Path(r) / rid
                if cand.is_dir():
                    return str(cand)

            # bounded scan (top N recent dirs in each root)
            SCAN_CAP = int(os.environ.get("VSP_FP_SCAN_CAP", "2000"))
            try_prefix = rid.split("_")[0] if "_" in rid else rid  # e.g. VSP or RUN
            for r in roots:
                pr = Path(r)
                if not pr.is_dir():
                    continue
                try:
                    dirs = [d for d in pr.iterdir() if d.is_dir()]
                except Exception:
                    continue
                # prioritize name match first
                dirs_name = [d for d in dirs if (d.name == rid or d.name.startswith(rid))]
                if dirs_name:
                    # pick newest
                    dirs_name.sort(key=lambda d: d.stat().st_mtime, reverse=True)
                    return str(dirs_name[0])

                # then bounded recent scan
                try:
                    dirs.sort(key=lambda d: d.stat().st_mtime, reverse=True)
                except Exception:
                    pass
                checked = 0
                for d in dirs:
                    if checked >= SCAN_CAP:
                        break
                    checked += 1
                    n = d.name
                    # cheap filters
                    if try_prefix and (try_prefix not in n):
                        continue
                    if (rid in n) or n.endswith(rid):
                        return str(d)
            return None

        def _vsp__load_findings(rid: str, run_dir: str):
            # try common locations
            rd = Path(run_dir)
            candidates = [
                rd / "findings_unified.json",
                rd / "reports" / "findings_unified.json",
                rd / "reports" / "findings_unified.sarif",  # fallback (not ideal)
            ]
            fp = None
            for c in candidates:
                if c.is_file():
                    fp = c
                    break
            if fp is None:
                return None, None, None, "findings file missing"

            # file size guard
            try:
                sz = fp.stat().st_size
            except Exception:
                sz = -1
            max_mb = int(os.environ.get("VSP_FP_MAX_MB", "60"))
            if sz >= 0 and sz > max_mb * 1024 * 1024:
                return str(fp), None, None, f"file too large ({sz} bytes) > {max_mb}MB"

            raw = fp.read_text(encoding="utf-8", errors="replace")
            j = json.loads(raw)
            # expected schema: {"meta":..., "findings":[...]}
            meta = j.get("meta") if isinstance(j, dict) else None
            findings = None
            if isinstance(j, dict):
                if isinstance(j.get("findings"), list):
                    findings = j["findings"]
                elif isinstance(j.get("items"), list):
                    findings = j["items"]
            if findings is None:
                return str(fp), meta, None, "unexpected findings schema"
            return str(fp), meta, findings, None

        def _vsp_findings_page_v3():
            t0 = time.time()
            if request is None or jsonify is None:
                return (json.dumps({"ok": False, "err": "flask not available"}), 500, {"Content-Type": "application/json"})

            rid = (request.args.get("rid") or "").strip()
            # pagination
            try:
                offset = int(request.args.get("offset") or "0")
            except Exception:
                offset = 0
            try:
                limit = int(request.args.get("limit") or "200")
            except Exception:
                limit = 200
            if offset < 0: offset = 0
            if limit < 1: limit = 1
            limit_cap = int(os.environ.get("VSP_FP_LIMIT_CAP", "400"))
            if limit > limit_cap: limit = limit_cap

            debug = (request.args.get("debug") or "").strip() in ("1","true","yes","on")

            if not rid:
                return jsonify({"ok": False, "err": "missing rid"}), 400

            run_dir = _vsp__bounded_find_run_dir(rid)
            if not run_dir:
                return jsonify({"ok": False, "err": "rid not found", "rid": rid}), 200

            # cache by (rid, mtime)
            try:
                # choose canonical findings path first to get mtime
                rd = Path(run_dir)
                fp0 = rd / "findings_unified.json"
                if not fp0.is_file():
                    fp0 = rd / "reports" / "findings_unified.json"
                mtime = fp0.stat().st_mtime if fp0.is_file() else 0.0
            except Exception:
                mtime = 0.0

            if _VSP_FP_CACHE.get("rid") == rid and _VSP_FP_CACHE.get("run_dir") == run_dir and _VSP_FP_CACHE.get("mtime") == mtime and _VSP_FP_CACHE.get("findings") is not None:
                findings = _VSP_FP_CACHE["findings"]
                meta = _VSP_FP_CACHE["meta"]
                fp = _VSP_FP_CACHE.get("fp")
                total = int(_VSP_FP_CACHE.get("total") or (len(findings) if findings else 0))
            else:
                fp, meta, findings, err = _vsp__load_findings(rid, run_dir)
                if err:
                    out = {"ok": False, "err": err, "rid": rid, "run_dir": run_dir}
                    if debug:
                        out["fp"] = fp
                    return jsonify(out), 200
                total = len(findings)
                _VSP_FP_CACHE.update({
                    "rid": rid, "run_dir": run_dir, "fp": fp, "mtime": mtime,
                    "total": total, "meta": meta, "findings": findings, "ts": time.time()
                })

            page = findings[offset: offset + limit] if findings else []
            out = {
                "ok": True,
                "rid": rid,
                "run_dir": run_dir,
                "offset": offset,
                "limit": limit,
                "total": total,
                "page_len": len(page),
                "page": page,
            }
            # small meta (optional)
            if isinstance(meta, dict):
                # keep it lean: only counts if present
                counts = meta.get("counts_by_severity") or meta.get("counts") or None
                if counts is not None:
                    out["counts"] = counts

            out["ms"] = int((time.time() - t0) * 1000)
            if debug:
                out["fp_cache_hit"] = bool(_VSP_FP_CACHE.get("ts")) and (_VSP_FP_CACHE.get("rid") == rid)
            return jsonify(out), 200

        # 1) allowlist patch
        _added = _vsp__patch_allowlists_for_findings_page()
        try:
            if _added:
                print("[VSP_FP_V3] allowlist patched for /api/vsp/findings_page")
        except Exception:
            pass

        # 2) force-bind route into Flask app (override if already exists)
        _app = _vsp__pick_flask_app()
        if _app is not None and hasattr(_app, "url_map") and hasattr(_app, "view_functions"):
            existing_ep = None
            try:
                for r in _app.url_map.iter_rules():
                    if getattr(r, "rule", None) == _VSP_FINDINGS_PAGE_PATH:
                        existing_ep = r.endpoint
                        break
            except Exception:
                existing_ep = None

            if existing_ep:
                # override handler
                _app.view_functions[existing_ep] = _vsp_findings_page_v3
                try:
                    print(f"[VSP_FP_V3] override endpoint={existing_ep} path={_VSP_FINDINGS_PAGE_PATH}")
                except Exception:
                    pass
            else:
                # new rule
                try:
                    _app.add_url_rule(_VSP_FINDINGS_PAGE_PATH, endpoint="api_vsp_findings_page_v3", view_func=_vsp_findings_page_v3, methods=["GET"])
                    print(f"[VSP_FP_V3] added path={_VSP_FINDINGS_PAGE_PATH}")
                except Exception as e:
                    try:
                        print("[VSP_FP_V3] add_url_rule failed:", repr(e))
                    except Exception:
                        pass

    except Exception as _e:
        try:
            print("[VSP_P0_FINDINGS_PAGE_V3_ALLOW_FORCEBIND_V1] failed:", repr(_e))
        except Exception:
            pass
    # ===================== /VSP_P0_FINDINGS_PAGE_V3_ALLOW_FORCEBIND_V1 =====================
    ''').lstrip("\n")

    p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
    print("[OK] appended findings_page V3 allow+forcebind at EOF")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile passed"

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: findings_page must be allowed + ok=true =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or j.get("items") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
echo "[RID]=$RID"
curl -fsS "$BASE/api/vsp/findings_page?rid=$RID&offset=0&limit=3&debug=1" \
| python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"total=",j.get("total"),"page_len=",j.get("page_len"),"err=",j.get("err"))
if j.get("ok"):
  p=j.get("page") or []
  if p:
    print("first_keys=", sorted(list(p[0].keys()))[:12])
PY

echo "[DONE]"
