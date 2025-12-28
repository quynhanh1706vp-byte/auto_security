#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

F="$(ls -1 static/js/vsp_ui_extras_*.js 2>/dev/null | sort | tail -n1 || true)"
[ -n "$F" ] || { echo "[ERR] cannot find static/js/vsp_ui_extras_*.js"; exit 2; }

cp -f "$F" "$F.bak_p0_ids_${TS}"
echo "[BACKUP] $F.bak_p0_ids_${TS}"

TARGET_FILE="$F" python3 - <<'PY'
import os
from pathlib import Path

p = Path(os.environ["TARGET_FILE"])
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "P0_DOM_FORM_IDS_FIX_V1"
if MARK not in s:
    addon = r"""
/* P0_DOM_FORM_IDS_FIX_V1: auto-fix duplicate ids + missing name/id for form fields */
(function(){
  'use strict';
  function run(){
    try{
      // 1) Fix duplicate IDs
      const byId = {};
      const all = Array.from(document.querySelectorAll("[id]"));
      for (const el of all){
        const id = el.getAttribute("id");
        if (!id) continue;
        byId[id] = byId[id] || [];
        byId[id].push(el);
      }
      for (const id of Object.keys(byId)){
        const arr = byId[id];
        if (arr.length <= 1) continue;
        for (let i=1;i<arr.length;i++){
          arr[i].setAttribute("id", id + "__dup" + i);
        }
        try{ console.info("[P0_IDS] fixed duplicate id:", id, "count=", arr.length); }catch(_){}
      }

      // 2) Ensure form controls have id or name (Chrome Issues)
      const ctrls = Array.from(document.querySelectorAll("input,select,textarea"));
      let k = 0;
      for (const el of ctrls){
        const tag = (el.tagName||"x").toLowerCase();
        const id = (el.getAttribute("id")||"").trim();
        const name = (el.getAttribute("name")||"").trim();
        if (!id && !name){
          const nid = "vsp_auto_" + tag + "_" + (++k);
          el.setAttribute("id", nid);
          el.setAttribute("name", nid);
        } else if (!name && id){
          el.setAttribute("name", id);
        } else if (!id && name){
          el.setAttribute("id", name);
        }
      }
    }catch(e){
      try{ console.warn("[P0_IDS] fixer error:", e && e.message ? e.message : e); }catch(_){}
    }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run, {once:true});
  else run();
})();
"""
    s = s + "\n" + addon
    p.write_text(s, encoding="utf-8")
    print("[OK] appended", MARK, "=>", p)
else:
    print("[OK] already patched", MARK, "=>", p)
PY

node --check "$F" >/dev/null && echo "[OK] node --check $F"
echo "[DONE] ids fix patch v2 => $F"
