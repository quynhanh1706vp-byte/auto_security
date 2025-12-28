/* VSP_JSON_VIEWER_V1 (P401) - stable JSON panels (no observer), predictable 100% */
(function(){
  "use strict";
  const NS = (window.VSP = window.VSP || {});

  if (NS.jsonViewer && NS.jsonViewer.__ver === "V1_P401") return;

  function esc(s){
    return String(s)
      .replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;")
      .replaceAll('"',"&quot;").replaceAll("'","&#39;");
  }
  function isObj(x){ return x && typeof x === "object" && !Array.isArray(x); }
  function el(tag, attrs, html){
    const e = document.createElement(tag);
    if (attrs) for (const [k,v] of Object.entries(attrs)) {
      if (k === "class") e.className = v;
      else if (k === "style") e.setAttribute("style", v);
      else e.setAttribute(k, v);
    }
    if (html !== undefined) e.innerHTML = html;
    return e;
  }

  function injectCssOnce(){
    if (document.getElementById("vsp_json_viewer_css_v1")) return;
    const css = `
      .vsp-jsonv-wrap{ border:1px solid rgba(255,255,255,.10); border-radius:12px; padding:10px; background:rgba(0,0,0,.20); }
      .vsp-jsonv-toolbar{ display:flex; gap:8px; align-items:center; margin:0 0 8px 0; flex-wrap:wrap; }
      .vsp-jsonv-btn{ cursor:pointer; border:1px solid rgba(255,255,255,.15); background:rgba(255,255,255,.06); color:#eaeaea; padding:6px 10px; border-radius:10px; font-size:12px; }
      .vsp-jsonv-btn:hover{ background:rgba(255,255,255,.10); }
      .vsp-jsonv-note{ opacity:.75; font-size:12px; }
      .vsp-jsonv-tree{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size:12px; line-height:1.45; }
      .vsp-jsonv-tree details{ margin:2px 0 2px 0; padding-left:10px; border-left:1px dashed rgba(255,255,255,.10); }
      .vsp-jsonv-tree summary{ cursor:pointer; list-style:none; user-select:none; }
      .vsp-jsonv-tree summary::-webkit-details-marker{ display:none; }
      .vsp-jsonv-k{ color:#9ad; }
      .vsp-jsonv-t{ opacity:.7; }
      .vsp-jsonv-v{ color:#ddd; }
      .vsp-jsonv-null{ color:#f99; }
      .vsp-jsonv-bool{ color:#9f9; }
      .vsp-jsonv-num{ color:#fd9; }
      .vsp-jsonv-str{ color:#9df; }
      .vsp-jsonv-small{ opacity:.75; font-size:11px; }
    `;
    const st = el("style", { id:"vsp_json_viewer_css_v1" }, css);
    document.head.appendChild(st);
  }

  function renderValue(key, value, depth, maxDepth){
    const k = (key === null ? "" : `<span class="vsp-jsonv-k">${esc(key)}</span>: `);

    if (value === null) return el("div", null, `${k}<span class="vsp-jsonv-null">null</span>`);
    if (typeof value === "boolean") return el("div", null, `${k}<span class="vsp-jsonv-bool">${value}</span>`);
    if (typeof value === "number") return el("div", null, `${k}<span class="vsp-jsonv-num">${value}</span>`);
    if (typeof value === "string") return el("div", null, `${k}<span class="vsp-jsonv-str">"${esc(value)}"</span>`);
    if (typeof value !== "object") return el("div", null, `${k}<span class="vsp-jsonv-v">${esc(String(value))}</span>`);

    const isArr = Array.isArray(value);
    const len = isArr ? value.length : Object.keys(value).length;
    const typeTag = isArr ? `array(${len})` : `object(${len})`;

    const d = el("details", { class:"vsp-jsonv-node" });
    if (depth === 0) d.open = true;

    const summary = el("summary", null,
      `${k}<span class="vsp-jsonv-t">${typeTag}</span> <span class="vsp-jsonv-small">(depth ${depth})</span>`
    );
    d.appendChild(summary);

    if (depth >= maxDepth) {
      d.appendChild(el("div", { class:"vsp-jsonv-small" }, `… truncated at maxDepth=${maxDepth}`));
      return d;
    }

    const container = el("div");
    if (isArr) {
      for (let i=0;i<value.length;i++){
        container.appendChild(renderValue(String(i), value[i], depth+1, maxDepth));
      }
    } else {
      const keys = Object.keys(value);
      keys.sort();
      for (const kk of keys){
        container.appendChild(renderValue(kk, value[kk], depth+1, maxDepth));
      }
    }
    d.appendChild(container);
    return d;
  }

  function setAllDetailsOpen(root, open){
    root.querySelectorAll("details").forEach(d => { d.open = !!open; });
  }

  function render(targetEl, data, opts){
    injectCssOnce();
    const maxDepth = Math.max(1, Math.min(10, (opts && opts.maxDepth) ? opts.maxDepth : 6));
    const title = (opts && opts.title) ? String(opts.title) : "JSON";

    const wrap = el("div", { class:"vsp-jsonv-wrap" });
    const tb = el("div", { class:"vsp-jsonv-toolbar" });
    const bOpen = el("button", { class:"vsp-jsonv-btn", type:"button" }, "Expand all");
    const bClose = el("button", { class:"vsp-jsonv-btn", type:"button" }, "Collapse all");
    const note = el("span", { class:"vsp-jsonv-note" }, `${title} • stable collapsible • maxDepth=${maxDepth}`);
    tb.appendChild(bOpen); tb.appendChild(bClose); tb.appendChild(note);

    const tree = el("div", { class:"vsp-jsonv-tree" });
    tree.appendChild(renderValue(null, data, 0, maxDepth));

    bOpen.addEventListener("click", () => setAllDetailsOpen(tree, true));
    bClose.addEventListener("click", () => setAllDetailsOpen(tree, false));

    wrap.appendChild(tb);
    wrap.appendChild(tree);

    targetEl.innerHTML = "";
    targetEl.appendChild(wrap);
  }

  NS.jsonViewer = { __ver:"V1_P401", render };
})();
