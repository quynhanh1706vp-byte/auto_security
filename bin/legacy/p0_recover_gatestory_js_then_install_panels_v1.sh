#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need date; need python3; need grep; need ls; need head; need sort; need node

JS="static/js/vsp_dashboard_gate_story_v1.js"
PJS="static/js/vsp_dashboard_commercial_panels_v1.js"
WSGI="wsgi_vsp_ui_gateway.py"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS"   "${JS}.bak_before_recover_${TS}"
cp -f "$WSGI" "${WSGI}.bak_before_recover_${TS}"
echo "[BACKUP] ${JS}.bak_before_recover_${TS}"
echo "[BACKUP] ${WSGI}.bak_before_recover_${TS}"

echo "== [1/3] recover GateStory JS to latest VALID backup (node --check) =="
GOOD=""
# ưu tiên các backup gần nhất
for f in $(ls -1t ${JS}.bak_* 2>/dev/null || true); do
  if node --check "$f" >/dev/null 2>&1; then
    GOOD="$f"
    break
  fi
done

if [ -z "$GOOD" ]; then
  echo "[ERR] cannot find any GateStory backup passing: node --check"
  echo "      List backups: ls -1t ${JS}.bak_* | head"
  exit 2
fi

cp -f "$GOOD" "$JS"
echo "[OK] restored GateStory from: $GOOD"
node --check "$JS"
echo "[OK] node --check GateStory OK"

echo "== [2/3] ensure external panels JS exists (create if missing) =="
if [ ! -f "$PJS" ]; then
  cat > "$PJS" <<'JSX'
/* VSP_P1_PANELS_EXTERNAL_V1 (safe + contract-flexible) */
(()=> {
  if (window.__vsp_p1_panels_ext_v1) return;
  window.__vsp_p1_panels_ext_v1 = true;

  function $(q,root){ return (root||document).querySelector(q); }
  function el(tag){ return document.createElement(tag); }

  async function getJSON(url){
    const r = await fetch(url, {credentials:"same-origin"});
    const t = await r.text();
    try { return JSON.parse(t); } catch(e){ return {ok:false, err:"bad_json", _text:t.slice(0,220)}; }
  }

  function unwrap(j){
    if (!j) return null;
    if (j.meta && Array.isArray(j.findings)) return j;
    const d = j.data || null;
    if (d && d.meta && Array.isArray(d.findings)) return d;
    return null;
  }

  function ridFromText(){
    const t = (document.body && (document.body.innerText||"")) || "";
    const m = t.match(/VSP_[A-Z0-9_]+_RUN_[0-9]{8}_[0-9]{6}/) || t.match(/RUN_[0-9]{8}_[0-9]{6}/);
    return m ? m[0] : null;
  }

  function ensureHost(){
    const root = $("#vsp5_root") || document.body;
    let host = $("#vsp_p1_panels_ext_host");
    if (!host){
      host = el("div");
      host.id = "vsp_p1_panels_ext_host";
      host.style.margin = "14px";
      host.style.padding = "12px";
      host.style.border = "1px solid rgba(255,255,255,.10)";
      host.style.borderRadius = "16px";
      host.style.background = "rgba(255,255,255,.03)";
      host.innerHTML = '<div style="font-size:12px;opacity:.9;margin-bottom:8px">Commercial Panels</div>' +
                       '<div id="vsp_p1_panels_ext_body" style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px"></div>';
      root.appendChild(host);
    }
    return host;
  }

  function card(title, value){
    const c = el("div");
    c.style.border = "1px solid rgba(255,255,255,.10)";
    c.style.borderRadius = "14px";
    c.style.padding = "10px 12px";
    c.style.background = "rgba(0,0,0,.18)";
    c.innerHTML = `<div style="font-size:12px;opacity:.85">${title}</div>
                   <div style="font-size:18px;font-weight:700;margin-top:6px">${value}</div>`;
    return c;
  }

  async function main(){
    const rid = ridFromText();
    const host = ensureHost();
    const body = $("#vsp_p1_panels_ext_body", host);
    if (!body) return;

    if (!rid){
      body.innerHTML = '<div style="opacity:.8;font-size:12px">No RID detected yet.</div>';
      console.log("[P1PanelsExtV1] no rid");
      return;
    }

    const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`;
    const raw = await getJSON(url);
    const j = unwrap(raw);
    if (!j){
      body.innerHTML = `<div style="opacity:.8;font-size:12px">Payload mismatch. keys=${Object.keys(raw||{}).join(",")}</div>`;
      console.log("[P1PanelsExtV1] payload mismatch", raw);
      return;
    }

    const c = (j.meta && j.meta.counts_by_severity) ? j.meta.counts_by_severity : {};
    const total = Array.isArray(j.findings) ? j.findings.length : 0;

    body.innerHTML = "";
    body.appendChild(card("RID", rid));
    body.appendChild(card("Findings total", String(total)));
    body.appendChild(card("CRITICAL/HIGH", `${c.CRITICAL||0}/${c.HIGH||0}`));
    body.appendChild(card("MED/LOW/INFO", `${c.MEDIUM||0}/${c.LOW||0}/${c.INFO||0}`));

    console.log("[P1PanelsExtV1] rendered rid=", rid, "total=", total, "counts=", c);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ()=> setTimeout(main, 50));
  } else {
    setTimeout(main, 50);
  }
})();
JSX
  echo "[OK] wrote $PJS"
else
  echo "[OK] panels JS exists: $PJS"
fi
node --check "$PJS"
echo "[OK] node --check panels OK"

echo "== [3/3] ensure /vsp5 HTML includes panels script =="
python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "vsp_dashboard_commercial_panels_v1.js" in s:
    print("[OK] panels include already present")
else:
    anchor = "<script src=\"/static/js/vsp_dashboard_gate_story_v1.js?v={asset_v}\"></script>"
    ins    = anchor + "\n  " + "<script src=\"/static/js/vsp_dashboard_commercial_panels_v1.js?v={asset_v}\"></script>"
    if anchor in s:
        s = s.replace(anchor, ins, 1)
        print("[OK] inserted panels include after GateStory include")
    else:
        # fallback: insert trước </body>
        j = s.find("</body>")
        if j < 0:
            raise SystemExit("[ERR] cannot find </body> to insert include")
        s = s[:j] + "  " + "<script src=\"/static/js/vsp_dashboard_commercial_panels_v1.js?v={asset_v}\"></script>\n" + s[j:]
        print("[OK] inserted panels include before </body> (fallback)")
    p.write_text(s, encoding="utf-8")

import py_compile
py_compile.compile("wsgi_vsp_ui_gateway.py", doraise=True)
print("[OK] py_compile WSGI OK")
PY

echo
echo "[DONE] Now restart UI then Ctrl+Shift+R /vsp5"
echo "[VERIFY] HTML has both scripts:"
echo "  curl -fsS http://127.0.0.1:8910/vsp5 | grep -nE 'gate_story_v1|commercial_panels_v1' || true"
