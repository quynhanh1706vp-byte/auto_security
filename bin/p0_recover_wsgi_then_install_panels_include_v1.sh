#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need sort; need head; need grep

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_before_recover_${TS}"
echo "[BACKUP] ${WSGI}.bak_before_recover_${TS}"

echo "== [1/3] find latest COMPILABLE backup and restore =="
CAND=""
# ưu tiên các .bak_* gần nhất
for f in $(ls -1t ${WSGI}.bak_* 2>/dev/null || true); do
  python3 -m py_compile "$f" >/dev/null 2>&1 && { CAND="$f"; break; }
done

if [ -n "${CAND}" ]; then
  cp -f "$CAND" "$WSGI"
  echo "[OK] restored WSGI from: $CAND"
else
  echo "[WARN] no compilable backup found -> try to sanitize current WSGI"
  python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace").splitlines(True)
out=[]
fixed=0
for line in s:
    if line.lstrip().startswith("\\1</html>") or "\\1</html>" in line:
        # remove accidental regex backref artifact
        line=line.replace("\\1</html>", "</html>")
        fixed+=1
    if line.lstrip().startswith("\\1</body>") or "\\1</body>" in line:
        line=line.replace("\\1</body>", "</body>")
        fixed+=1
    # nếu có dòng standalone bắt đầu bằng \1... gây SyntaxError, drop luôn
    if line.startswith("\\1</") and ('html' in line or 'body' in line):
        fixed+=1
        continue
    out.append(line)
p.write_text("".join(out), encoding="utf-8")
print("[OK] sanitized possible '\\\\1' artifacts:", fixed)
PY
fi

python3 -m py_compile "$WSGI"
echo "[OK] py_compile WSGI OK after recover/sanitize"

echo "== [2/3] ensure external panels JS exists (create if missing) =="
PJS="static/js/vsp_dashboard_commercial_panels_v1.js"
if [ ! -f "$PJS" ]; then
  cat > "$PJS" <<'JS'
/* VSP_P1_PANELS_EXTERNAL_V1 (safe + contract-flexible) */
(()=> {
  if (window.__vsp_p1_panels_ext_v1) return;
  window.__vsp_p1_panels_ext_v1 = true;

  function $(q,root){ return (root||document).querySelector(q); }
  function el(tag, cls){ const n=document.createElement(tag); if(cls) n.className=cls; return n; }

  async function getJSON(url){
    const r = await fetch(url, {credentials:"same-origin"});
    const t = await r.text();
    try { return JSON.parse(t); } catch(e){ return {ok:false, err:"bad_json", _text:t.slice(0,220)}; }
  }

  function unwrapFindingsPayload(j){
    // chấp nhận 2 dạng:
    // A) {meta:{counts_by_severity...}, findings:[...]}
    // B) {ok:true, data:{meta..., findings...}} hoặc {data:{...}}
    if (!j) return null;
    if (j.findings && j.meta) return j;
    const d = j.data || (j.ok && j.data) || null;
    if (d && d.findings && d.meta) return d;
    return null;
  }

  function getRIDFromPage(){
    // ưu tiên RID hiển thị trên page
    const t = document.body ? (document.body.innerText||"") : "";
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
    const rid = getRIDFromPage();
    const host = ensureHost();
    const body = $("#vsp_p1_panels_ext_body", host);
    if (!body) return;

    if (!rid){
      body.innerHTML = '<div style="opacity:.8;font-size:12px">No RID detected (will show when RID appears).</div>';
      console.log("[P1PanelsExtV1] no rid yet");
      return;
    }

    // lấy findings_unified.json qua run_file_allow (đã allow)
    const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`;
    const raw = await getJSON(url);
    const j = unwrapFindingsPayload(raw);
    if (!j){
      body.innerHTML = `<div style="opacity:.8;font-size:12px">Findings payload mismatch. keys=${Object.keys(raw||{}).join(",")}</div>`;
      console.log("[P1PanelsExtV1] payload mismatch", raw);
      return;
    }

    const c = (j.meta && j.meta.counts_by_severity) ? j.meta.counts_by_severity : {};
    const total = (j.findings && Array.isArray(j.findings)) ? j.findings.length : 0;

    body.innerHTML = "";
    body.appendChild(card("RID", rid));
    body.appendChild(card("Findings total", String(total)));
    body.appendChild(card("CRITICAL/HIGH", `${c.CRITICAL||0}/${c.HIGH||0}`));
    body.appendChild(card("MED/LOW/INFO", `${c.MEDIUM||0}/${c.LOW||0}/${c.INFO||0}`));

    console.log("[P1PanelsExtV1] rendered rid=", rid, "total=", total, "counts=", c);
  }

  // chạy sau khi DOM ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ()=> setTimeout(main, 50));
  } else {
    setTimeout(main, 50);
  }
})();
JS
  echo "[OK] wrote $PJS"
else
  echo "[OK] panels JS exists: $PJS"
fi

python3 - <<'PY'
import py_compile
py_compile.compile("static/js/vsp_dashboard_gate_story_v1.js", doraise=True)
print("[OK] GateStory JS file exists (syntax not checked by py_compile, but OK to serve).")
PY

echo "== [3/3] patch /vsp5 HTML to include panels script safely =="
python3 - <<'PY'
from pathlib import Path
import re, time

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "vsp_dashboard_commercial_panels_v1.js" in s:
    print("[OK] panels include already present in WSGI")
else:
    # chỉ insert trong HTML /vsp5: tìm vùng có <title>VSP5</title> rồi insert trước </body> đầu tiên sau đó
    idx = s.find("<title>VSP5</title>")
    if idx < 0:
        # fallback: insert trước </body> cuối file
        s2 = s.replace("</body>", '  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js?v={asset_v}"></script>\n</body>', 1)
        if s2 == s:
            raise SystemExit("[ERR] cannot find </body> to insert")
        s = s2
        print("[OK] inserted panels include before first </body> (fallback)")
    else:
        j = s.find("</body>", idx)
        if j < 0:
            raise SystemExit("[ERR] cannot find </body> after <title>VSP5</title>")
        insert = '  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js?v={asset_v}"></script>\n'
        s = s[:j] + insert + s[j:]
        print("[OK] inserted panels include before </body> in /vsp5 HTML region")

p.write_text(s, encoding="utf-8")
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile WSGI OK after insert"

echo
echo "[DONE] Next steps:"
echo "  1) restart UI service (:8910) (systemd/gunicorn)"
echo "  2) Ctrl+Shift+R /vsp5"
echo
echo "[VERIFY] HTML must include BOTH scripts:"
echo "  curl -fsS http://127.0.0.1:8910/vsp5 | grep -nE 'gate_story_v1|commercial_panels_v1' || true"
