#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

# ---------- [1] create python module: apply overrides ----------
PYMOD="vsp_rule_overrides_apply_v1.py"
[ -f "$PYMOD" ] && cp -f "$PYMOD" "$PYMOD.bak_${TS}" && echo "[BACKUP] $PYMOD.bak_${TS}"

cat > "$PYMOD" <<'PY'
# vsp_rule_overrides_apply_v1.py
from __future__ import annotations
import os, json, re, hashlib
from datetime import datetime, timezone
from typing import Any, Dict, List, Tuple, Optional

SEV6 = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]

def _now_utc() -> datetime:
    return datetime.now(timezone.utc)

def _parse_dt(v: Any) -> Optional[datetime]:
    if v is None: return None
    if isinstance(v, (int, float)):
        try: return datetime.fromtimestamp(float(v), tz=timezone.utc)
        except Exception: return None
    if isinstance(v, str):
        s=v.strip()
        if not s: return None
        # accept "2025-12-16T00:00:00Z" or "+00:00"
        s2 = s.replace("Z", "+00:00")
        try:
            dt = datetime.fromisoformat(s2)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except Exception:
            return None
    return None

def _norm_sev(sev: Any) -> str:
    s = (sev or "").strip().upper()
    if s in SEV6: return s
    # tolerate common variants
    m = {
        "CRIT":"CRITICAL",
        "INFORMATIONAL":"INFO",
        "INFORMATION":"INFO",
        "TRIVIAL":"TRACE",
    }
    if s in m: return m[s]
    return "INFO" if s else "INFO"

def _allowed_set_sev(sev: Any) -> Optional[str]:
    if sev is None: return None
    s = str(sev).strip().upper()
    return s if s in SEV6 else None

def _sha1(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8", "ignore")).hexdigest()

def finding_key(f: Dict[str,Any]) -> str:
    # stable-ish key if upstream doesn't provide id
    tool = str(f.get("tool","") or "")
    rule = str(f.get("rule_id", f.get("rule","")) or "")
    cwe  = ",".join([str(x) for x in (f.get("cwe") or [])]) if isinstance(f.get("cwe"), list) else str(f.get("cwe","") or "")
    file = str(f.get("file","") or "")
    line = str(f.get("line","") or "")
    title= str(f.get("title","") or "")
    return _sha1("|".join([tool,rule,cwe,file,line,title])[:2000])

def _rx(pat: Any) -> Optional[re.Pattern]:
    if not pat: return None
    try:
        return re.compile(str(pat), re.IGNORECASE)
    except Exception:
        return None

def _get_overrides_list(doc: Any) -> List[Dict[str,Any]]:
    if doc is None: return []
    if isinstance(doc, list):
        return [x for x in doc if isinstance(x, dict)]
    if isinstance(doc, dict):
        for k in ("overrides","items","rules","data"):
            v = doc.get(k)
            if isinstance(v, list):
                return [x for x in v if isinstance(x, dict)]
    return []

def load_overrides_file(path: str) -> Tuple[Dict[str,Any], List[Dict[str,Any]]]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            doc = json.load(f)
    except Exception:
        return ({"ok":False, "path":path, "error":"read_failed"}, [])
    lst = _get_overrides_list(doc)
    meta = {"ok":True, "path":path, "count":len(lst)}
    # keep some top-level meta if exists
    if isinstance(doc, dict):
        for k in ("mode","updated_ts","updated_by","version"):
            if k in doc: meta[k]=doc.get(k)
    return (meta, lst)

def _ov_enabled(ov: Dict[str,Any]) -> bool:
    if ov.get("enabled") is False: return False
    if ov.get("disabled") is True: return False
    return True

def _ov_match_dict(ov: Dict[str,Any]) -> Dict[str,Any]:
    m = ov.get("match") if isinstance(ov.get("match"), dict) else {}
    # support flat fields too
    flat_keys = ("tool","rule_id","rule","cwe","file_regex","title_regex","path_regex","severity","id","finding_id")
    for k in flat_keys:
        if k in ov and k not in m:
            m[k]=ov.get(k)
    return m

def _ov_action_dict(ov: Dict[str,Any]) -> Dict[str,Any]:
    a = ov.get("action") if isinstance(ov.get("action"), dict) else {}
    # tolerate flat action fields
    if "suppress" in ov and "suppress" not in a: a["suppress"]=ov.get("suppress")
    if "set_severity" in ov and "set_severity" not in a: a["set_severity"]=ov.get("set_severity")
    if "severity" in ov and "set_severity" not in a and ov.get("severity") in SEV6: a["set_severity"]=ov.get("severity")
    return a

def _match_one(ov: Dict[str,Any], f: Dict[str,Any]) -> bool:
    m = _ov_match_dict(ov)
    # direct id match
    fid = m.get("finding_id") or m.get("id")
    if fid:
        # allow override to store our computed key too
        if str(f.get("finding_id","")) == str(fid): return True
        if str(f.get("id","")) == str(fid): return True
        if finding_key(f) == str(fid): return True

    tool = str(m.get("tool","") or "").strip().lower()
    if tool and str(f.get("tool","") or "").strip().lower() != tool:
        return False

    rule = m.get("rule_id") or m.get("rule")
    if rule:
        fr = f.get("rule_id", f.get("rule"))
        if str(fr or "") != str(rule):
            return False

    # cwe match: allow list/string
    cwe = m.get("cwe")
    if cwe:
        fc = f.get("cwe")
        fc_s = set([str(x) for x in (fc or [])]) if isinstance(fc, list) else set([str(fc)])
        want = set([str(x) for x in cwe]) if isinstance(cwe, list) else set([str(cwe)])
        if want and not (want & fc_s):
            return False

    sev = m.get("severity")
    if sev:
        if _norm_sev(f.get("severity")) != _norm_sev(sev):
            return False

    # regexes
    frx = _rx(m.get("file_regex") or m.get("path_regex"))
    if frx:
        if not frx.search(str(f.get("file","") or "")):
            return False

    trx = _rx(m.get("title_regex"))
    if trx:
        if not trx.search(str(f.get("title","") or "")):
            return False

    # if override provided at least one constraint, accept; if it provided none, do NOT match everything
    has_any = any([tool, rule, cwe, sev, frx, trx, fid])
    return bool(has_any)

def apply_overrides(findings: List[Dict[str,Any]], overrides: List[Dict[str,Any]], now: Optional[datetime]=None) -> Tuple[List[Dict[str,Any]], Dict[str,Any]]:
    now = now or _now_utc()
    suppressed_n=0
    changed_severity_n=0
    expired_n=0
    applied_n=0

    eff: List[Dict[str,Any]] = []

    for f in findings:
        f2 = dict(f)
        f2.setdefault("finding_id", f.get("finding_id") or f.get("id") or finding_key(f))
        matched: Optional[Dict[str,Any]] = None
        for ov in overrides:
            if not isinstance(ov, dict): 
                continue
            if not _ov_enabled(ov):
                continue
            exp = _parse_dt(ov.get("expires_at") or ov.get("expire_at") or ov.get("until"))
            if exp and exp < now:
                # expired override is ignored but counted if it WOULD match
                if _match_one(ov, f2):
                    expired_n += 1
                continue
            if _match_one(ov, f2):
                matched = ov
                break

        if not matched:
            eff.append(f2)
            continue

        applied_n += 1
        act = _ov_action_dict(matched)
        suppress = bool(act.get("suppress") is True)
        setsev = _allowed_set_sev(act.get("set_severity"))

        # annotate (commercial)
        f2["override_id"] = matched.get("id") or matched.get("override_id") or None
        f2["override_note"] = matched.get("note") or matched.get("reason") or matched.get("comment") or None

        if setsev:
            old = _norm_sev(f2.get("severity"))
            if old != setsev:
                f2["severity_before_override"] = old
                f2["severity"] = setsev
                changed_severity_n += 1

        if suppress:
            suppressed_n += 1
            continue

        eff.append(f2)

    delta = {
        "applied_n": applied_n,
        "suppressed_n": suppressed_n,
        "changed_severity_n": changed_severity_n,
        "expired_n": expired_n,
        "now_utc": now.isoformat(),
    }
    return eff, delta

def summarize(findings: List[Dict[str,Any]]) -> Dict[str,Any]:
    by_sev = {k:0 for k in SEV6}
    by_tool: Dict[str,int] = {}
    for f in findings:
        s = _norm_sev(f.get("severity"))
        by_sev[s] = by_sev.get(s,0) + 1
        t = str(f.get("tool","") or "UNKNOWN")
        by_tool[t] = by_tool.get(t,0) + 1
    return {"total": len(findings), "by_severity": by_sev, "by_tool": by_tool}

def apply_file(findings_path: str, overrides_path: str, out_path: str) -> Dict[str,Any]:
    with open(findings_path, "r", encoding="utf-8") as f:
        doc = json.load(f)
    items = doc.get("items") if isinstance(doc, dict) else None
    if not isinstance(items, list):
        raise RuntimeError("bad_findings_format: missing .items[]")
    _, ovs = load_overrides_file(overrides_path)
    eff, delta = apply_overrides(items, ovs)
    raw_sum = summarize(items)
    eff_sum = summarize(eff)
    out_doc = {
        "ok": True,
        "generated_at_utc": _now_utc().isoformat(),
        "source_findings": os.path.abspath(findings_path),
        "source_overrides": os.path.abspath(overrides_path),
        "delta": delta,
        "raw_summary": raw_sum,
        "effective_summary": eff_sum,
        "items": eff,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out_doc, f, ensure_ascii=False, indent=2)
    return out_doc
PY

# ---------- [2] create CLI helper ----------
mkdir -p bin
CLISH="bin/vsp_apply_rule_overrides_run_dir_v1.sh"
[ -f "$CLISH" ] && cp -f "$CLISH" "$CLISH.bak_${TS}" && echo "[BACKUP] $CLISH.bak_${TS}"

cat > "$CLISH" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="${1:-}"
[ -n "$RUN_DIR" ] || { echo "Usage: $0 <RUN_DIR> [OVERRIDES_JSON]"; exit 2; }

OV="${2:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_rule_overrides_v1.json}"
F_RAW="$RUN_DIR/findings_unified.json"
F_OUT="$RUN_DIR/findings_effective.json"

[ -f "$F_RAW" ] || { echo "[ERR] missing $F_RAW"; exit 3; }
[ -f "$OV" ] || { echo "[ERR] missing overrides: $OV"; exit 4; }

python3 - <<PY
import json, sys
from vsp_rule_overrides_apply_v1 import apply_file
out = apply_file("$F_RAW", "$OV", "$F_OUT")
print("[OK] wrote", "$F_OUT")
print(json.dumps({"delta": out.get("delta"), "effective_total": out.get("effective_summary",{}).get("total")}, ensure_ascii=False, indent=2))
PY
BASH
chmod +x "$CLISH"

# ---------- [3] patch backend: add endpoints into vsp_demo_app.py ----------
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 10; }
cp -f "$APP" "$APP.bak_rules_apply_${TS}" && echo "[BACKUP] $APP.bak_rules_apply_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="### VSP_RULE_OVERRIDES_APPLY_PREVIEW_V1 ###"
if MARK in s:
    print("[SKIP] marker already present in vsp_demo_app.py")
    raise SystemExit(0)

# try to inject before last "if __name__ == '__main__':" if present, else append
inject_point = None
m = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
if m:
    inject_point = m.start()
else:
    inject_point = len(s)

block = f"""
\n{MARK}
# NOTE: commercial P0: preview/apply rule overrides -> effective findings
import os, json, urllib.request, urllib.error
from datetime import datetime, timezone
from flask import request, jsonify

try:
    from vsp_rule_overrides_apply_v1 import load_overrides_file, apply_overrides, summarize
except Exception as _e:
    load_overrides_file = None
    apply_overrides = None
    summarize = None

def _vsp_http_get_json_local(path: str, timeout_sec: float = 2.5):
    # avoid hardcoding host; fall back to localhost if request context missing
    base = None
    try:
        base = request.host_url.rstrip('/')
    except Exception:
        base = "http://127.0.0.1:8910"
    url = base + path
    req = urllib.request.Request(url, headers={{"Accept":"application/json"}})
    with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
        data = resp.read()
    return json.loads(data.decode("utf-8", "ignore"))

def _vsp_get_run_dir_from_statusv2(rid: str):
    st = _vsp_http_get_json_local(f"/api/vsp/run_status_v2/{{rid}}")
    rd = st.get("ci_run_dir") or st.get("ci") or st.get("run_dir")
    return rd, st

def _vsp_get_overrides_path():
    return os.environ.get("VSP_RULE_OVERRIDES_FILE") or "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_rule_overrides_v1.json"

def _vsp_load_findings_items(run_dir: str):
    f = os.path.join(run_dir, "findings_unified.json")
    if not os.path.isfile(f):
        return None, f, "findings_unified_not_found"
    try:
        doc = json.load(open(f, "r", encoding="utf-8"))
    except Exception:
        return None, f, "findings_unified_read_failed"
    items = doc.get("items") if isinstance(doc, dict) else None
    if not isinstance(items, list):
        return None, f, "findings_unified_bad_format"
    return items, f, None

def _vsp_apply_overrides_preview(rid: str):
    if not (load_overrides_file and apply_overrides and summarize):
        return {{"ok":False, "error":"apply_module_missing"}}

    run_dir, st = _vsp_get_run_dir_from_statusv2(rid)
    if not run_dir:
        return {{"ok":False, "rid":rid, "error":"run_dir_not_resolved", "statusv2": st}}

    items, fpath, err = _vsp_load_findings_items(run_dir)
    if err:
        return {{"ok":False, "rid":rid, "run_dir":run_dir, "error":err, "file":fpath}}

    ov_path = _vsp_get_overrides_path()
    meta, ovs = load_overrides_file(ov_path)
    now = datetime.now(timezone.utc)
    eff, delta = apply_overrides(items, ovs, now=now)

    out = {{
        "ok": True,
        "rid": rid,
        "run_dir": run_dir,
        "overrides": meta,
        "delta": delta,
        "raw_summary": summarize(items),
        "effective_summary": summarize(eff),
        # return effective items for datasource
        "items": eff,
        "raw_total": len(items),
        "effective_total": len(eff),
    }}
    return out

# GET: preview effective findings (raw+effective+delta)
if "api_vsp_findings_effective_v1" not in getattr(app, "view_functions", {{}}):
    @app.get("/api/vsp/findings_effective_v1/<rid>")
    def api_vsp_findings_effective_v1(rid):
        limit = int(request.args.get("limit", "200"))
        offset = int(request.args.get("offset", "0"))
        view = (request.args.get("view") or "effective").lower()  # effective|raw
        out = _vsp_apply_overrides_preview(rid)
        if not out.get("ok"):
            return jsonify(out), 200

        # optional raw view (no overrides)
        if view == "raw":
            run_dir = out.get("run_dir")
            items, fpath, err = _vsp_load_findings_items(run_dir)
            if err:
                return jsonify({{"ok":False,"rid":rid,"error":err,"file":fpath}}), 200
            out["items"] = items

        items = out.get("items") or []
        out["items_n"] = len(items)
        out["items"] = items[offset: offset+limit]
        out["offset"] = offset
        out["limit"] = limit
        out["view"] = view
        return jsonify(out), 200

# POST: apply and persist findings_effective.json to RUN_DIR
if "api_vsp_rule_overrides_apply_v1" not in getattr(app, "view_functions", {{}}):
    @app.post("/api/vsp/rule_overrides_apply_v1/<rid>")
    def api_vsp_rule_overrides_apply_v1(rid):
        out = _vsp_apply_overrides_preview(rid)
        if not out.get("ok"):
            return jsonify(out), 200
        run_dir = out.get("run_dir")
        f_out = os.path.join(run_dir, "findings_effective.json")
        try:
            with open(f_out, "w", encoding="utf-8") as f:
                json.dump(out, f, ensure_ascii=False, indent=2)
            out["persisted_file"] = f_out
            out["persist_ok"] = True
        except Exception as e:
            out["persist_ok"] = False
            out["persist_error"] = str(e)
        return jsonify(out), 200
"""
s2 = s[:inject_point] + block + "\n" + s[inject_point:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected endpoints into vsp_demo_app.py")
PY

# ---------- [4] patch Data Source tab to use effective endpoint ----------
JS="static/js/vsp_datasource_tab_v1.js"
[ -f "$JS" ] || { echo "[WARN] missing $JS (skip UI patch)"; goto_verify=1; }

if [ -f "$JS" ]; then
  cp -f "$JS" "$JS.bak_effective_${TS}" && echo "[BACKUP] $JS.bak_effective_${TS}"

  python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_datasource_tab_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# replace findings_preview endpoint -> findings_effective
s2 = s.replace("/api/vsp/findings_preview_v1", "/api/vsp/findings_effective_v1")

# add small delta banner if not present
if "VSP_DS_EFFECTIVE_BANNER_V1" not in s2:
    banner = r"""
/* VSP_DS_EFFECTIVE_BANNER_V1: show delta from rule overrides (suppressed/changed/expired) */
(function(){
  try{
    const el = document.getElementById("vsp4-datasource") || document.querySelector("[data-tab='datasource']");
    if(!el) return;
    const box = document.createElement("div");
    box.id = "vsp-ds-effective-banner";
    box.style.cssText = "margin:10px 0;padding:10px 12px;border:1px solid rgba(148,163,184,.25);border-radius:10px;background:rgba(2,6,23,.35);color:#cbd5e1;font-size:12px;";
    box.innerHTML = '<b>Rule Overrides</b>: <span id="vsp-ds-delta">loading...</span>';
    el.prepend(box);

    window.__vspDsSetDelta = function(delta){
      const d = delta || {};
      const txt = `suppressed=${d.suppressed_n||0} | changed_sev=${d.changed_severity_n||0} | expired=${d.expired_n||0}`;
      const t = document.getElementById("vsp-ds-delta");
      if(t) t.textContent = txt;
    };
  }catch(e){ console.warn("[VSP_DS_EFFECTIVE_BANNER_V1] err", e); }
})();
"""
    s2 = s2 + "\n" + banner

# try to hook after fetch parsing: out.delta -> banner
# naive injection: find "const data = await res.json()" and add update call
if "__vspDsSetDelta" in s2 and "data.delta" not in s2:
    s2 = re.sub(r"(const\s+data\s*=\s*await\s+res\.json\(\)\s*;)",
                r"\1\n      try{ if(window.__vspDsSetDelta) window.__vspDsSetDelta(data.delta||{}); }catch(e){}",
                s2, count=1)

p.write_text(s2, encoding="utf-8")
print("[OK] patched datasource tab to use findings_effective_v1 + delta banner")
PY
fi

# ---------- [5] verify ----------
python3 -m py_compile vsp_demo_app.py vsp_rule_overrides_apply_v1.py
echo "[OK] py_compile OK"

if [ -f "static/js/vsp_datasource_tab_v1.js" ]; then
  node --check static/js/vsp_datasource_tab_v1.js >/dev/null && echo "[OK] node --check datasource OK"
fi

echo "[DONE] patch_rule_overrides_apply_preview_v1"
echo "Next: restart gunicorn UI (8910), hard refresh browser (Ctrl+Shift+R)."
