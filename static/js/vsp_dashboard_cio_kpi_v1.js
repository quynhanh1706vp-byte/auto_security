(function(){
  window.__VSP_CIO_KPI_LOADED = true;

  'use strict';

  function q(sel, root){ return (root || document).querySelector(sel); }
  function ce(tag, cls, txt){
    var el = document.createElement(tag);
    if (cls) el.className = cls;
    if (typeof txt === 'string') el.textContent = txt;
    return el;
  }
  function esc(s){
    return String(s).replace(/[&<>"']/g, function(c){
      return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]);
    });
  }

  function getJSON(url){
    return fetch(url, {credentials:'same-origin'}).then(function(r){
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    });
  }

  function pickCounts(obj){
    // cố gắng lấy severity counts từ nhiều dạng payload khác nhau
    var out = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
    if (!obj || typeof obj !== 'object') return out;

    // case: obj.counts / obj.severity / obj.summary
    var cand = obj.counts || obj.severity || obj.summary || obj.kpi || null;
    if (cand && typeof cand === 'object') {
      Object.keys(out).forEach(function(k){
        var v = cand[k];
        if (typeof v === 'number') out[k] = v;
      });
    }

    // case: obj.items (list) -> sum by severity
    if (Array.isArray(obj.items)) {
      obj.items.forEach(function(it){
        var s = (it && (it.sev || it.severity || it.severity_norm)) || '';
        s = String(s).toUpperCase();
        if (out.hasOwnProperty(s)) out[s] += 1;
      });
    }
    return out;
  }

  function ensureContainer(){
    var c = q('#vsp_cio_kpi_root');
    if (c) return c;

    // inject top of body (or top of main wrapper if exists)
    c = ce('div', 'vsp-cio-kpi-root');
    c.id = 'vsp_cio_kpi_root';

    var host = q('#vsp_dashboard_root') || q('#app') || document.body;
    if (host.firstChild) host.insertBefore(c, host.firstChild);
    else host.appendChild(c);

    // minimal inline style (không phá theme hiện có)
    var st = ce('style');
    st.textContent =  '.vsp-cio-kpi-root{margin:12px 0;position:relative;z-index:50;}' +  '.vsp-cio-kpi-grid{display:grid;grid-template-columns:repeat(6,minmax(140px,1fr));gap:10px;padding:6px 10px;}' +  '@media (max-width:1200px){.vsp-cio-kpi-grid{grid-template-columns:repeat(3,minmax(140px,1fr));}}' +  '@media (max-width:700px){.vsp-cio-kpi-grid{grid-template-columns:repeat(2,minmax(140px,1fr));}}' +  '.vsp-cio-kpi-card{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.10);border-radius:14px;padding:10px 12px;cursor:pointer;user-select:none;}' +  '.vsp-cio-kpi-card:hover{transform:translateY(-1px);transition:transform 120ms ease;}' +  '.vsp-cio-kpi-top{display:flex;justify-content:space-between;gap:8px;align-items:center;}' +  '.vsp-cio-kpi-title{font-size:12px;opacity:0.85;letter-spacing:0.3px;}' +  '.vsp-cio-kpi-num{font-size:22px;font-weight:800;line-height:1.1;}' +  '.vsp-cio-kpi-sub{margin-top:6px;font-size:12px;opacity:0.75;}' +  '.vsp-cio-kpi-meta{padding:0 10px 8px 10px;font-size:12px;opacity:0.85;display:flex;gap:12px;flex-wrap:wrap;}' +  '.vsp-cio-kpi-root, .vsp-cio-kpi-card{color:inherit;}' ;}' +
      '.vsp-cio-kpi-grid{display:grid;grid-template-columns:repeat(6,minmax(140px,1fr));gap:10px;padding:6px 10px;}' +
      '@media (max-width:1200px){.vsp-cio-kpi-grid{grid-template-columns:repeat(3,minmax(140px,1fr));}}' +
      '@media (max-width:700px){.vsp-cio-kpi-grid{grid-template-columns:repeat(2,minmax(140px,1fr));}}' +
      '.vsp-cio-kpi-card{border:1px solid rgba(255,255,255,0.08);border-radius:14px;padding:10px 12px;cursor:pointer;user-select:none;}' +
      '.vsp-cio-kpi-card:hover{transform:translateY(-1px);transition:transform 120ms ease;}' +
      '.vsp-cio-kpi-top{display:flex;justify-content:space-between;gap:8px;align-items:center;}' +
      '.vsp-cio-kpi-title{font-size:12px;opacity:0.8;letter-spacing:0.3px;}' +
      '.vsp-cio-kpi-num{font-size:22px;font-weight:700;line-height:1.1;}' +
      '.vsp-cio-kpi-sub{margin-top:6px;font-size:12px;opacity:0.7;}' +
      '.vsp-cio-kpi-meta{padding:0 10px 8px 10px;font-size:12px;opacity:0.75;display:flex;gap:12px;flex-wrap:wrap;}';
    document.head.appendChild(st);

    return c;
  }

  function goDataSourceFilter(payload){
    // payload: {severity:"CRITICAL", q:"", tool:""}
    var qs = new URLSearchParams();
    if (payload && payload.severity) qs.set('severity', payload.severity);
    if (payload && payload.q) qs.set('q', payload.q);
    if (payload && payload.tool) qs.set('tool', payload.tool);
    window.location.href = '/data_source?' + qs.toString();
  }

  function render(counts, meta){
    var root = ensureContainer();
    root.innerHTML = '';

    var metaLine = ce('div', 'vsp-cio-kpi-meta');
    metaLine.innerHTML =
      '<span><b>Last RID</b>: ' + esc(meta && meta.rid ? meta.rid : 'N/A') + '</span>' +
      '<span><b>Source</b>: /api/vsp/top_findings_v2</span>' +
      (meta && meta.degraded ? '<span><b>Degraded</b>: ' + esc(meta.degraded) + '</span>' : '');
    root.appendChild(metaLine);

    var grid = ce('div', 'vsp-cio-kpi-grid');
    root.appendChild(grid);

    function addCard(label, sev){
      var card = ce('div', 'vsp-cio-kpi-card');
      var num = (counts && typeof counts[sev] === 'number') ? counts[sev] : 0;
      var top = ce('div', 'vsp-cio-kpi-top');
      top.appendChild(ce('div', 'vsp-cio-kpi-title', label));
      top.appendChild(ce('div', 'vsp-cio-kpi-num', String(num)));
      card.appendChild(top);
      card.appendChild(ce('div', 'vsp-cio-kpi-sub', 'Click to drill-down'));
      card.addEventListener('click', function(){
        goDataSourceFilter({severity: sev});
      });
      grid.appendChild(card);
    }

    addCard('CRITICAL', 'CRITICAL');
    addCard('HIGH', 'HIGH');
    addCard('MEDIUM', 'MEDIUM');
    addCard('LOW', 'LOW');
    addCard('INFO', 'INFO');
    addCard('TRACE', 'TRACE');
  }

  
/* VSP_P960E_AUTOPICK_RID */
function boot(){
  function okCounts(j){
    return j && typeof j === 'object' && (j.ok === true || j.ok === 1 || !('ok' in j));
  }
  function getLatestRID(){
    return getJSON('/api/ui/runs_v3?limit=1&include_ci=1').then(function(r){
      var it = (r && r.items && r.items[0]) ? r.items[0] : null;
      var rid = it && (it.rid || it.run_id || it.id) ? (it.rid || it.run_id || it.id) : '';
      return String(rid || '');
    }).catch(function(){ return ''; });
  }

  // 1) try without rid (for cached deployments)
  getJSON('/api/vsp/top_findings_v2?limit=200').then(function(j){
    if (okCounts(j)) {
      var counts = pickCounts(j);
      var meta = {
        rid: j && (j.rid || j.run_id || j.latest_rid) ? (j.rid || j.run_id || j.latest_rid) : '',
        degraded: j && (j.degraded || j.degraded_tools || j.degraded_count) ? (j.degraded || j.degraded_tools || j.degraded_count) : ''
      };
      render(counts, meta);
      return;
    }
    // 2) fallback: pick latest rid then call with rid
    return getLatestRID().then(function(rid){
      if (!rid) {
        render({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0}, {rid:'N/A', degraded:'no runs'});
        return;
      }
      return getJSON('/api/vsp/top_findings_v2?rid=' + encodeURIComponent(rid) + '&limit=200').then(function(j2){
        var counts2 = pickCounts(j2);
        var meta2 = {
          rid: rid,
          degraded: j2 && (j2.degraded || j2.degraded_tools || j2.degraded_count) ? (j2.degraded || j2.degraded_tools || j2.degraded_count) : ''
        };
        render(counts2, meta2);
      }).catch(function(err2){
        render({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0}, {rid:rid, degraded:'top_findings_failed'});
        console.warn('[VSP CIO KPI] rid fallback failed:', err2);
      });
    });
  }).catch(function(err){
    // 3) even first call failed -> still attempt rid fallback
    getLatestRID().then(function(rid){
      if (!rid) {
        render({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0}, {rid:'N/A', degraded:'no runs'});
        return;
      }
      return getJSON('/api/vsp/top_findings_v2?rid=' + encodeURIComponent(rid) + '&limit=200').then(function(j2){
        var counts2 = pickCounts(j2);
        render(counts2, {rid:rid, degraded:''});
      }).catch(function(){
        render({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0}, {rid:rid, degraded:'top_findings_failed'});
      });
    });
    console.warn('[VSP CIO KPI] load failed:', err);
  });
}
)();


/* VSP_P963_USE_KPI_COUNTS_V1 */
(function(){
  try{
    // override boot() if exists
    if (typeof boot !== 'function') return;

    function getLatestRID(){
      return getJSON('/api/ui/runs_v3?limit=1&include_ci=1').then(function(r){
        var it = (r && r.items && r.items[0]) ? r.items[0] : null;
        var rid = it && (it.rid || it.run_id || it.id) ? (it.rid || it.run_id || it.id) : '';
        return String(rid || '');
      }).catch(function(){ return ''; });
    }

    // shadow boot with reliable KPI source
    boot = function(){
      getLatestRID().then(function(rid){
        if(!rid){
          render({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0},{rid:'N/A',degraded:'no runs'});
          return;
        }
        return getJSON('/api/vsp/kpi_counts_v2?rid=' + encodeURIComponent(rid)).then(function(j){
          var counts = (j && j.counts) ? j.counts : pickCounts(j);
          var meta = {rid: rid, degraded: (j && j.degraded) ? j.degraded : ''};
          render(counts, meta);
        }).catch(function(err){
          render({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0},{rid:rid,degraded:'kpi_counts_failed'});
          console.warn('[VSP CIO KPI] kpi_counts_v1 failed:', err);
        });
      });
    };
  }catch(e){
    console.warn('[VSP CIO KPI] P963 patch init failed:', e);
  }
})();


/* VSP_P963G_WIRE_V2 */
(function(){
  try{
    console.log('[VSP CIO KPI] P963G loaded', new Date().toISOString());

    function ridFromURL(){
      try{
        var sp = new URLSearchParams(window.location.search || '');
        var rid = sp.get('rid') || sp.get('RID') || '';
        return String(rid||'').trim();
      }catch(e){ return ''; }
    }

    function setText(sel, v){
      var el = document.querySelector(sel);
      if(!el) return false;
      el.textContent = String(v);
      return true;
    }

    function updateExistingKPIs(counts){
      var total = 0;
      ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){ total += (counts[k]||0); });

      // common ids
      setText('#kpi_total', total);
      setText('#kpi_critical', counts.CRITICAL||0);
      setText('#kpi_high', counts.HIGH||0);
      setText('#kpi_medium', counts.MEDIUM||0);
      setText('#kpi_low', counts.LOW||0);
      setText('#kpi_info', counts.INFO||0);
      setText('#kpi_trace', counts.TRACE||0);

      // data attrs
      ['TOTAL','CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){
        var v = (k==='TOTAL') ? total : (counts[k]||0);
        var el = document.querySelector('[data-kpi="'+k+'"],[data-kpi-key="'+k+'"],[data-sev="'+k+'"]');
        if (el) el.textContent = String(v);
      });
    }

    function forceBlock(counts, meta){
      var root = document.getElementById('vsp_cio_kpi_root');
      if(!root) return;

      root.innerHTML = '';
      var h = document.createElement('div');
      h.className='vsp-cio-kpi-meta';
      h.innerHTML = '<b>CIO KPI (v2)</b> rid=<code>'+String(meta && meta.rid || '')+'</code> n='+String(meta && meta.n || '')+'';
      root.appendChild(h);

      var g = document.createElement('div');
      g.className='vsp-cio-kpi-grid';
      ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'].forEach(function(k){
        var c = document.createElement('div');
        c.className='vsp-cio-kpi-card';
        c.innerHTML =
          '<div class="vsp-cio-kpi-top"><div class="vsp-cio-kpi-title">'+k+'</div><div class="vsp-cio-kpi-num">'+(counts[k]||0)+'</div></div>' +
          '<div class="vsp-cio-kpi-sub">click to drill-down</div>';
        c.addEventListener('click', function(){
          window.location.href = '/data_source?severity='+encodeURIComponent(k);
        });
        g.appendChild(c);
      });
      root.appendChild(g);
    }

    function fetchV2(rid){
      return fetch('/api/vsp/kpi_counts_v2?rid='+encodeURIComponent(rid), {credentials:'same-origin'})
        .then(function(r){ return r.json(); });
    }

    // Shadow boot: rid-from-URL first, else keep existing logic
    if (typeof boot === 'function') {
      var oldBoot = boot;
      boot = function(){
        var rid = ridFromURL();
        if(!rid){ oldBoot(); return; }
        fetchV2(rid).then(function(j){
          var counts = (j && j.counts) ? j.counts : {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
          updateExistingKPIs(counts);
          forceBlock(counts, {rid: rid, n: (j && j.n)||0});
        }).catch(function(e){
          console.warn('[VSP CIO KPI] kpi_counts_v2 failed', e);
          oldBoot();
        });
      };
    }
  }catch(e){
    console.warn('[VSP CIO KPI] P963G init error', e);
  }
})();
