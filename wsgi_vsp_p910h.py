# P910H5_WSGI_WRAPPER (force run_status NO_RID => 200, add header)
import json, datetime
from pathlib import Path
from urllib.parse import parse_qs
from werkzeug.wrappers import Response

from vsp_demo_app import app as _flask_app

def _resp(obj, status=200):
    body = json.dumps(obj, ensure_ascii=False)
    r = Response(body, status=status, mimetype="application/json; charset=utf-8")
    r.headers["X-VSP-WRAP"] = "P910H5"
    return r

def _pick_latest_release_dir():
    root = Path(__file__).resolve().parent
    relroot = root / "out_ci" / "releases"
    if not relroot.exists():
        return None
    dirs = sorted([d for d in relroot.glob("RELEASE_UI_*") if d.is_dir()],
                  key=lambda p: p.stat().st_mtime, reverse=True)
    return dirs[0] if dirs else None

def _read_text(p, limit=200000):
    try:
        return Path(p).read_text(encoding="utf-8", errors="replace")[:limit]
    except Exception:
        return ""

def _read_json(p):
    try:
        return json.loads(Path(p).read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return None

def _qs_first(qs: str, key: str) -> str:
    try:
        q = parse_qs(qs or "", keep_blank_values=True)
        if key not in q or not q[key]:
            return ""
        return (q[key][0] or "").strip()
    except Exception:
        return ""

def _rid_garbage(rid: str) -> bool:
    if not rid:
        return True
    rl = rid.strip().lower()
    return (rl in ("undefined","null","none","nan")) or rl.startswith("undefined") or rl == ""

class _Middleware:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO","") or "")
        qs   = (environ.get("QUERY_STRING","") or "")

        # (A) HARD FIX: stop 400/404 spam forever
        if path.rstrip("/") == "/api/vsp/run_status_v1":
            rid = _qs_first(qs, "rid")
            if _rid_garbage(rid):
                return _resp({"ok": False, "rid": None, "state": "NO_RID"}, 200)(environ, start_response)
            # if rid looks real, just pass-through to Flask (keeps behavior)
            return self.app(environ, start_response)

        # (B) ops_latest must ALWAYS be JSON
        if path.rstrip("/") == "/api/vsp/ops_latest_v1":
            out = {
                "ok": False,
                "source": {"release_dir": "", "ops_dir": "", "ts": datetime.datetime.now().isoformat()},
                "stamp": None,
                "journal_tail": "",
                "errors": []
            }
            try:
                rel = _pick_latest_release_dir()
                if not rel:
                    out["errors"].append("no_release_dir")
                    return _resp(out, 200)(environ, start_response)
                ops = rel / "evidence" / "ops"
                out["source"]["release_dir"] = str(rel)
                out["source"]["ops_dir"] = str(ops)

                stamp_p = ops / "stamp" / "OPS_STAMP.json"
                proof_p = ops / "proof" / "PROOF.txt"
                health_dir = ops / "healthcheck"

                stamp = _read_json(stamp_p) if stamp_p.exists() else None
                out["stamp"] = stamp

                journal_txt = ""
                if isinstance(stamp, dict) and stamp.get("journal_tail"):
                    journal_txt = str(stamp.get("journal_tail"))
                else:
                    cand = []
                    for n in ["journal_tail.txt","JOURNAL_TAIL.txt","journal.txt"]:
                        fp = ops / "stamp" / n
                        if fp.exists(): cand.append(fp)
                    if cand:
                        cand.sort(key=lambda p: p.stat().st_mtime, reverse=True)
                        journal_txt = _read_text(cand[0], limit=20000)
                out["journal_tail"] = journal_txt

                if health_dir.exists():
                    files = [p for p in health_dir.rglob("*") if p.is_file()]
                    if files:
                        files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
                        best = files[0]
                        out["source"]["health_file"] = str(best)
                        if best.suffix.lower()==".json":
                            out["healthcheck"] = _read_json(best)
                        else:
                            out["healthcheck_text"] = _read_text(best, limit=20000)

                if proof_p.exists():
                    out["proof"] = _read_text(proof_p, limit=20000)

                ok = False
                if isinstance(stamp, dict):
                    http = stamp.get("http_code")
                    listen = stamp.get("listen")
                    ok = (str(http)=="200") and (str(listen) in ("1","true","True"))
                out["ok"] = bool(ok)

            except Exception as e:
                out["errors"].append("exception:" + str(e))

            return _resp(out, 200)(environ, start_response)

        return self.app(environ, start_response)

app = _Middleware(_flask_app.wsgi_app)
