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
    expired_match_n=0
    matched_n=0
    applied_effect_n=0

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
                    expired_match_n += 1
                continue
            if _match_one(ov, f2):
                matched = ov
                break

        if not matched:
            eff.append(f2)
            continue

        matched_n += 1
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
                applied_effect_n += 1

        if suppress:
            suppressed_n += 1
            applied_effect_n += 1
            continue

        eff.append(f2)

    delta = {
        "matched_n": matched_n,
        "applied_n": applied_effect_n,  # EFFECTIVE changes only
        "suppressed_n": suppressed_n,
        "changed_severity_n": changed_severity_n,
        "expired_match_n": expired_match_n,
        "now_utc": now.isoformat(),
        "note": "applied_n counts only suppress/severity-change effects; matched_n counts matched overrides (non-expired)",
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
