#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date

TS="$(date +%Y%m%d_%H%M%S)"
ok(){ echo "[OK] $*"; }

backup(){
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "${f}.bak_p121b_${TS}"
  ok "backup: ${f}.bak_p121b_${TS}"
}

write_file(){
  local f="$1"
  backup "$f"
  cat > "$f" <<'JS'
/* placeholder */
JS
  ok "wrote: $f"
}

# ---------- /c/runs ----------
F="static/js/vsp_c_runs_v1.js"
backup "$F"
cat > "$F" <<'JS'
/* VSP_P121B_C_RUNS_V1 - safe, no template literal */
(function(){
  "use strict";

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); }
  function log(){ console.log.apply(console, ["[VSPC][runs]"].concat([].slice.call(arguments))); }
  function warn(){ console.warn.apply(console, ["[VSPC][runs]"].concat([].slice.call(arguments))); }

  function sanitizeRid(r){
    r = (r==null ? "" : String(r)).trim();
    r = r.replace(/[^\w\-:.]/g, "");
    if (r.length > 160) r = r.slice(0,160);
    return r;
  }
  function getParam(name){
    try { return (new URLSearchParams(location.search)).get(name) || ""; }
    catch(e){ return ""; }
  }
  function getRid(){
    var u = sanitizeRid(getParam("rid"));
    var ls = sanitizeRid(localStorage.getItem("VSP_C_RID") || "");
    return u || ls || "";
  }
  function setRid(rid){
    rid = sanitizeRid(rid);
    if (rid) localStorage.setItem("VSP_C_RID", rid);
    return rid;
  }

  function fetchJSON(url, timeoutMs){
    timeoutMs = timeoutMs || 9000;
    var ctl = new AbortController();
    var t = setTimeout(function(){ try{ctl.abort();}catch(e){} }, timeoutMs);
    return fetch(url, {signal: ctl.signal, cache:"no-store", credentials:"same-origin"})
      .then(function(r){
        return r.text().then(function(txt){
          var j=null; try{ j=JSON.parse(txt); }catch(e){}
          return {ok:r.ok, status:r.status, json:j, text:txt, url:url};
        });
      })
      .finally(function(){ clearTimeout(t); });
  }

  function firstOK(urls){
    var p = Promise.resolve(null);
    urls.forEach(function(u){
      p = p.then(function(prev){
        if (prev) return prev;
        return fetchJSON(u, 9000).then(function(res){
          if (res && res.ok && res.json) return res;
          return null;
        }).catch(function(){ return null; });
      });
    });
    return p;
  }

  function findRunsTable(){
    var tables = qsa("table");
    for (var i=0;i<tables.length;i++){
      var t = tables[i];
      var th = qsa("th", t).map(function(x){ return (x.textContent||"").trim().toLowerCase(); }).join("|");
      if (th.indexOf("rid")>=0 && th.indexOf("action")>=0) return t;
    }
    return qs("#runs_table") || qs("table");
  }

  function renderRows(tbody, items){
    tbody.innerHTML = "";
    for (var i=0;i<items.length;i++){
      var it = items[i] || {};
      var rid = sanitizeRid(it.rid || it.run_id || it.id || "");
      var label = String(it.label || it.ts || it.when || it.created_at || "");
      var verdict = String(it.verdict || it.overall || it.status || "");

      var tr = document.createElement("tr");

      var tdRid = document.createElement("td");
      tdRid.textContent = rid || "(none)";
      tdRid.style.whiteSpace = "nowrap";

      var tdLabel = document.createElement("td");
      tdLabel.textContent = label;

      var tdAct = document.createElement("td");
      tdAct.style.whiteSpace = "nowrap";

      function mkA(href, txt){
        var a=document.createElement("a");
        a.href=href; a.textContent=txt;
        a.style.marginRight="10px";
        return a;
      }

      if (rid){
        tdAct.appendChild(mkA("/c/dashboard?rid="+encodeURIComponent(rid), "Dashboard"));
        tdAct.appendChild(mkA("/api/vsp/export_findings_csv_v1?rid="+encodeURIComponent(rid), "CSV"));
        tdAct.appendChild(mkA("/api/vsp/export_reports_tgz_v1?rid="+encodeURIComponent(rid), "Reports.tgz"));
        if (verdict){
          var sp=document.createElement("span");
          sp.textContent = verdict;
          sp.style.opacity="0.75";
          sp.style.marginLeft="6px";
          tdAct.appendChild(sp);
        }
        var btn=document.createElement("button");
        btn.textContent="Use RID";
        btn.style.marginLeft="10px";
        btn.onclick=function(r){
          return function(){ setRid(r); location.href="/c/runs?rid="+encodeURIComponent(r); };
        }(rid);
        tdAct.appendChild(btn);
      } else {
        tdAct.textContent = verdict || "";
      }

      tr.appendChild(tdRid);
      tr.appendChild(tdLabel);
      tr.appendChild(tdAct);
      tbody.appendChild(tr);
    }
  }

  function main(){
    var rid = getRid();
    if (rid) log("rid=", rid);

    var tbl = findRunsTable();
    if (!tbl){ warn("table not found"); return; }

    var tb = qs("tbody", tbl);
    if (!tb){ tb=document.createElement("tbody"); tbl.appendChild(tb); }

    var inp = null;
    var ins = qsa("input");
    for (var i=0;i<ins.length;i++){
      var ph = (ins[i].placeholder||"").toLowerCase();
      if (ph.indexOf("filter")>=0){ inp=ins[i]; break; }
    }

    tb.innerHTML = '<tr><td colspan="3" style="opacity:.7">Loading...</td></tr>';

    firstOK([
      "/api/ui/runs_v3?limit=200&include_ci=1",
      "/api/vsp/runs_v3?limit=200&include_ci=1",
      "/api/vsp/runs_v2?limit=200"
    ]).then(function(res){
      if (!res){
        tb.innerHTML = '<tr><td colspan="3" style="color:#ffb">Cannot load runs API</td></tr>';
        return;
      }
      var items = res.json.items || res.json.data || res.json.runs || [];
      var norm = items.map(function(x){
        return {
          rid: x.rid || x.run_id || x.id,
          label: x.label || x.ts || x.when || x.created_at || "",
          verdict: x.verdict || x.overall || x.status || ""
        };
      });
      var view = norm.slice();
      renderRows(tb, view);

      if (inp){
        inp.addEventListener("input", function(){
          var q=(inp.value||"").toLowerCase().trim();
          if (!q){ view=norm.slice(); renderRows(tb, view); return; }
          view = norm.filter(function(x){
            return (String(x.rid||"").toLowerCase().indexOf(q)>=0) ||
                   (String(x.label||"").toLowerCase().indexOf(q)>=0);
          });
          renderRows(tb, view);
        });
      }
    }).catch(function(e){
      console.error(e);
      tb.innerHTML = '<tr><td colspan="3" style="color:#ffb">runs error</td></tr>';
    });
  }

  window.addEventListener("DOMContentLoaded", main);
})();
JS
ok "wrote: $F"

# ---------- /c/data_source ----------
F="static/js/vsp_c_data_source_v1.js"
backup "$F"
cat > "$F" <<'JS'
/* VSP_P121B_C_DATA_SOURCE_V1 - safe, no template literal */
(function(){
  "use strict";

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); }
  function log(){ console.log.apply(console, ["[VSPC][ds]"].concat([].slice.call(arguments))); }
  function warn(){ console.warn.apply(console, ["[VSPC][ds]"].concat([].slice.call(arguments))); }

  function sanitizeRid(r){
    r = (r==null ? "" : String(r)).trim();
    r = r.replace(/[^\w\-:.]/g, "");
    if (r.length > 160) r = r.slice(0,160);
    return r;
  }
  function getParam(name){
    try { return (new URLSearchParams(location.search)).get(name) || ""; }
    catch(e){ return ""; }
  }
  function getRid(){
    var u = sanitizeRid(getParam("rid"));
    var ls = sanitizeRid(localStorage.getItem("VSP_C_RID") || "");
    return u || ls || "";
  }

  function fetchJSON(url, timeoutMs){
    timeoutMs = timeoutMs || 9000;
    var ctl = new AbortController();
    var t = setTimeout(function(){ try{ctl.abort();}catch(e){} }, timeoutMs);
    return fetch(url, {signal: ctl.signal, cache:"no-store", credentials:"same-origin"})
      .then(function(r){
        return r.text().then(function(txt){
          var j=null; try{ j=JSON.parse(txt); }catch(e){}
          return {ok:r.ok, status:r.status, json:j, text:txt, url:url};
        });
      })
      .finally(function(){ clearTimeout(t); });
  }

  function firstOK(urls){
    var p = Promise.resolve(null);
    urls.forEach(function(u){
      p = p.then(function(prev){
        if (prev) return prev;
        return fetchJSON(u, 9000).then(function(res){
          if (res && res.ok && res.json) return res;
          return null;
        }).catch(function(){ return null; });
      });
    });
    return p;
  }

  function findDataTable(){
    var tables = qsa("table");
    var best=null, bestScore=-1;
    for (var i=0;i<tables.length;i++){
      var t=tables[i];
      var th = qsa("th", t).map(function(x){ return (x.textContent||"").trim().toLowerCase(); });
      var score = 0;
      if (th.indexOf("severity")>=0) score += 2;
      if (th.indexOf("title")>=0) score += 2;
      if (th.indexOf("tool")>=0) score += 1;
      if (th.indexOf("location")>=0) score += 1;
      if (th.length >= 6) score += 1;
      if (score > bestScore){ best=t; bestScore=score; }
    }
    return best || qs("table");
  }

  function td(v){
    var x=document.createElement("td");
    x.textContent = (v==null ? "" : String(v));
    return x;
  }

  function render(tbody, rows){
    tbody.innerHTML="";
    for (var i=0;i<rows.length;i++){
      var r=rows[i]||{};
      var tr=document.createElement("tr");
      tr.appendChild(td(r.id||""));
      tr.appendChild(td(r.tool||""));
      tr.appendChild(td(r.type||""));
      tr.appendChild(td(r.severity||""));
      tr.appendChild(td(r.title||""));
      tr.appendChild(td(r.component||""));
      tr.appendChild(td(r.version||""));
      tr.appendChild(td(r.location||""));
      tr.appendChild(td(r.fix||""));
      tbody.appendChild(tr);
    }
  }

  function main(){
    var rid = getRid();
    var tbl = findDataTable();
    if (!tbl){ warn("table not found"); return; }

    var tb = qs("tbody", tbl);
    if (!tb){ tb=document.createElement("tbody"); tbl.appendChild(tb); }

    var offset = 0;
    var limit = 200;

    function load(){
      tb.innerHTML = '<tr><td colspan="12" style="opacity:.7">Loading...</td></tr>';
      var r = encodeURIComponent(rid || "");
      var urls = [
        "/api/vsp/datasource_v3?rid="+r+"&limit="+limit+"&offset="+offset,
        "/api/vsp/datasource?rid="+r+"&limit="+limit+"&offset="+offset,
        "/api/vsp/findings_unified_v1?rid="+r+"&limit="+limit+"&offset="+offset,
        "/api/vsp/data_source_v1?rid="+r+"&limit="+limit+"&offset="+offset
      ];
      firstOK(urls).then(function(res){
        if (!res){
          tb.innerHTML = '<tr><td colspan="12" style="color:#ffb">Cannot load datasource API</td></tr>';
          return;
        }
        var j=res.json||{};
        var rows = j.items || j.rows || j.data || [];
        render(tb, rows);
        log("rows=", rows.length, "offset=", offset);
      }).catch(function(e){
        console.error(e);
        tb.innerHTML = '<tr><td colspan="12" style="color:#ffb">datasource error</td></tr>';
      });
    }

    // hook "Next" button if exists
    var nextBtn = null;
    var bs = qsa("button");
    for (var i=0;i<bs.length;i++){
      var t=(bs[i].textContent||"").toLowerCase();
      if (t.indexOf("next")>=0){ nextBtn=bs[i]; break; }
    }
    if (nextBtn){
      nextBtn.onclick = function(){ offset += limit; load(); };
    }

    load();
  }

  window.addEventListener("DOMContentLoaded", main);
})();
JS
ok "wrote: $F"

# ---------- /c/settings ----------
F="static/js/vsp_c_settings_v1.js"
backup "$F"
cat > "$F" <<'JS'
/* VSP_P121B_C_SETTINGS_V1 - safe */
(function(){
  "use strict";

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); }
  function log(){ console.log.apply(console, ["[VSPC][settings]"].concat([].slice.call(arguments))); }

  function sanitizeRid(r){
    r = (r==null ? "" : String(r)).trim();
    r = r.replace(/[^\w\-:.]/g, "");
    if (r.length > 160) r = r.slice(0,160);
    return r;
  }
  function getParam(name){
    try { return (new URLSearchParams(location.search)).get(name) || ""; }
    catch(e){ return ""; }
  }
  function getRid(){
    var u = sanitizeRid(getParam("rid"));
    var ls = sanitizeRid(localStorage.getItem("VSP_C_RID") || "");
    return u || ls || "";
  }

  function fetchJSON(url, timeoutMs){
    timeoutMs = timeoutMs || 8000;
    var ctl = new AbortController();
    var t = setTimeout(function(){ try{ctl.abort();}catch(e){} }, timeoutMs);
    return fetch(url, {signal: ctl.signal, cache:"no-store", credentials:"same-origin"})
      .then(function(r){
        return r.text().then(function(txt){
          var j=null; try{ j=JSON.parse(txt); }catch(e){}
          return {ok:r.ok, status:r.status, json:j, text:txt, url:url};
        });
      })
      .finally(function(){ clearTimeout(t); });
  }

  function firstOK(urls){
    var p = Promise.resolve(null);
    urls.forEach(function(u){
      p = p.then(function(prev){
        if (prev) return prev;
        return fetchJSON(u, 8000).then(function(res){
          if (res && res.ok && res.json) return res;
          return null;
        }).catch(function(){ return null; });
      });
    });
    return p;
  }

  function findProbeTable(){
    var tables = qsa("table");
    for (var i=0;i<tables.length;i++){
      var t=tables[i];
      var head = qsa("th", t).map(function(x){ return (x.textContent||"").trim().toLowerCase(); }).join("|");
      if (head.indexOf("endpoint")>=0 || head.indexOf("status")>=0) return t;
    }
    return null;
  }

  function main(){
    var rid = getRid();
    var pre = null;
    var pres = qsa("pre");
    for (var i=0;i<pres.length;i++){
      if ((pres[i].textContent||"").indexOf("{")>=0){ pre=pres[i]; break; }
    }

    var probes = [
      {name:"runs_v3", url:"/api/ui/runs_v3?limit=1&include_ci=1"},
      {name:"dashboard_kpis_v4", url:"/api/vsp/dashboard_kpis_v4" + (rid ? ("?rid="+encodeURIComponent(rid)) : "")},
      {name:"top_findings_v2", url:"/api/vsp/top_findings_v2?limit=1" + (rid ? ("&rid="+encodeURIComponent(rid)) : "")},
      {name:"trend_v1", url:"/api/vsp/trend_v1"}
    ];

    var t = findProbeTable();
    if (t){
      var tb = qs("tbody", t);
      if (!tb){ tb=document.createElement("tbody"); t.appendChild(tb); }
      tb.innerHTML = "";

      // sequential to keep it simple
      var seq = Promise.resolve();
      probes.forEach(function(p){
        seq = seq.then(function(){
          var tr=document.createElement("tr");
          var td1=document.createElement("td"); td1.textContent=p.name; td1.style.whiteSpace="nowrap";
          var td2=document.createElement("td"); td2.textContent="Loading..."; td2.style.opacity="0.7";
          tr.appendChild(td1); tr.appendChild(td2);
          tb.appendChild(tr);
          return fetchJSON(p.url, 7000).then(function(res){
            td2.textContent = res.ok ? ("OK ("+res.status+")") : ("FAIL ("+res.status+")");
          });
        });
      });
    }

    if (pre){
      firstOK(["/api/vsp/settings_v1", "/api/vsp/policy_v1", "/api/vsp/config_v1"])
        .then(function(res){
          if (res && res.json) pre.textContent = JSON.stringify(res.json, null, 2);
        });
    }

    log("ok rid=", rid || "(none)");
  }

  window.addEventListener("DOMContentLoaded", main);
})();
JS
ok "wrote: $F"

# ---------- /c/rule_overrides ----------
F="static/js/vsp_c_rule_overrides_v1.js"
backup "$F"
cat > "$F" <<'JS'
/* VSP_P121B_C_RULE_OVERRIDES_V1 - safe */
(function(){
  "use strict";

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); }
  function log(){ console.log.apply(console, ["[VSPC][ovr]"].concat([].slice.call(arguments))); }
  function warn(){ console.warn.apply(console, ["[VSPC][ovr]"].concat([].slice.call(arguments))); }

  function fetchJSON(url, timeoutMs){
    timeoutMs = timeoutMs || 8000;
    var ctl = new AbortController();
    var t = setTimeout(function(){ try{ctl.abort();}catch(e){} }, timeoutMs);
    return fetch(url, {signal: ctl.signal, cache:"no-store", credentials:"same-origin"})
      .then(function(r){
        return r.text().then(function(txt){
          var j=null; try{ j=JSON.parse(txt); }catch(e){}
          return {ok:r.ok, status:r.status, json:j, text:txt, url:url};
        });
      })
      .finally(function(){ clearTimeout(t); });
  }

  function firstOK(urls){
    var p = Promise.resolve(null);
    urls.forEach(function(u){
      p = p.then(function(prev){
        if (prev) return prev;
        return fetchJSON(u, 8000).then(function(res){
          if (res && res.ok && res.json) return res;
          return null;
        }).catch(function(){ return null; });
      });
    });
    return p;
  }

  function findEditor(){
    return qs("textarea") || qs("#rule_overrides_editor") || null;
  }

  function findBtn(exact){
    exact = (exact||"").toLowerCase();
    var bs = qsa("button");
    for (var i=0;i<bs.length;i++){
      var t=(bs[i].textContent||"").trim().toLowerCase();
      if (t === exact) return bs[i];
    }
    return null;
  }

  function loadBackend(){
    return firstOK(["/api/vsp/rule_overrides_v1", "/api/vsp/rule_overrides", "/api/vsp/overrides_v1"])
      .then(function(res){ return (res && res.json) ? res.json : null; });
  }

  function main(){
    var ed = findEditor();
    if (!ed){ warn("textarea not found"); return; }

    var key = "vsp_rule_overrides_v1";

    function doLoad(){
      return loadBackend().then(function(j){
        if (j){
          ed.value = JSON.stringify(j, null, 2);
          localStorage.setItem(key, ed.value);
          log("loaded from backend");
        } else {
          var s = localStorage.getItem(key) || '{"ok":false,"items":[]}';
          ed.value = s;
          log("loaded from localStorage");
        }
      });
    }

    function doSave(){
      var obj=null;
      try{ obj = JSON.parse(ed.value); }catch(e){ alert("JSON invalid"); return Promise.resolve(); }

      // best-effort POST
      return fetch("/api/vsp/rule_overrides_v1", {
        method:"POST",
        headers: {"Content-Type":"application/json"},
        body: JSON.stringify(obj),
        cache:"no-store",
        credentials:"same-origin"
      }).then(function(r){
        if (r.ok){
          localStorage.setItem(key, ed.value);
          alert("Saved (backend)");
          return;
        }
        localStorage.setItem(key, ed.value);
        alert("Saved (local)");
      }).catch(function(){
        localStorage.setItem(key, ed.value);
        alert("Saved (local)");
      });
    }

    function doExport(){
      var blob = new Blob([ed.value], {type:"application/json"});
      var a=document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "rule_overrides.json";
      a.click();
      setTimeout(function(){ try{URL.revokeObjectURL(a.href);}catch(e){} }, 500);
    }

    var bLoad = findBtn("load");
    var bSave = findBtn("save");
    var bExp  = findBtn("export");
    if (bLoad) bLoad.onclick = function(){ doLoad().catch(console.error); };
    if (bSave) bSave.onclick = function(){ doSave().catch(console.error); };
    if (bExp)  bExp.onclick  = function(){ doExport(); };

    doLoad().catch(console.error);
  }

  window.addEventListener("DOMContentLoaded", main);
})();
JS
ok "wrote: $F"

ok "P121b applied."
echo ""
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/runs"
echo "  http://127.0.0.1:8910/c/data_source"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
