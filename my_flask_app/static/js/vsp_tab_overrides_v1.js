(function () {
  if (!window.VSP) window.VSP = {};

  function createEl(tag, className, text) {
    var el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined && text !== null) el.textContent = text;
    return el;
  }

  function findNav(label) {
    label = label.toLowerCase();
    var nodes = document.querySelectorAll('a, button, div, span, li');
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      var txt = (n.textContent || "").trim().toLowerCase();
      if (!txt) continue;
      if (txt === label) return n;
    }
    return null;
  }

  function createOverlay(idSuffix) {
    var overlay = document.createElement("div");
    overlay.id = "vsp-overlay-" + idSuffix;
    overlay.style.position = "fixed";
    overlay.style.left = "0";
    overlay.style.top = "0";
    overlay.style.right = "0";
    overlay.style.bottom = "0";
    overlay.style.zIndex = "998";
    overlay.style.pointerEvents = "none";
    overlay.style.background = "rgba(3,7,30,0.98)";

    var inner = document.createElement("div");
    inner.style.position = "absolute";
    inner.style.left = "260px";
    inner.style.right = "24px";
    inner.style.top = "80px";
    inner.style.bottom = "24px";
    inner.style.pointerEvents = "auto";
    inner.style.overflow = "auto";

    overlay.appendChild(inner);
    overlay.style.display = "none";
    document.body.appendChild(overlay);

    return { overlay: overlay, inner: inner };
  }

  function pillSeverity(sev) {
    sev = (sev || "").toUpperCase();
    var span = createEl("span", "vsp-pill sev-" + sev, sev || "N/A");
    return span;
  }

  function renderSummary(holder, list) {
    holder.innerHTML = "";

    var header = createEl("div", "vsp-section-header");
    var title = createEl("div", "vsp-section-title-main", "Rule Overrides – Summary");
    var sub = createEl("div", "vsp-section-sub",
      "View and filter rule-based adjustments (severity change, false positives, ownership).");
    header.appendChild(title);
    header.appendChild(sub);

    holder.appendChild(header);

    var filterBar = createEl("div", "vsp-filter-bar");
    filterBar.style.display = "flex";
    filterBar.style.flexWrap = "wrap";
    filterBar.style.gap = "8px";
    filterBar.style.alignItems = "center";
    filterBar.style.marginTop = "12px";

    var fTool = createEl("input", "vsp-input");
    fTool.placeholder = "Filter by tool (e.g. semgrep, g)";
    var fSev = createEl("input", "vsp-input");
    fSev.placeholder = "Filter by new severity (e.g. l, c)";
    var fRule = createEl("input", "vsp-input");
    fRule.placeholder = "Search Rule ID";

    fTool.style.minWidth = "200px";
    fSev.style.minWidth = "200px";
    fRule.style.flex = "1 1 260px";

    var btnApply = createEl("button", "vsp-btn-primary", "Apply filters");

    filterBar.appendChild(fTool);
    filterBar.appendChild(fSev);
    filterBar.appendChild(fRule);
    filterBar.appendChild(btnApply);

    holder.appendChild(filterBar);

    var tableHost = createEl("div", "");
    tableHost.style.marginTop = "12px";
    holder.appendChild(tableHost);

    function apply() {
      var t = (fTool.value || "").toLowerCase();
      var s = (fSev.value || "").toLowerCase();
      var r = (fRule.value || "").toLowerCase();

      var filtered = list.filter(function (it) {
        var ok = true;
        if (t) ok = ok && ((it.tool || "").toLowerCase().indexOf(t) >= 0);
        if (s) ok = ok && ((it.new_severity || "").toLowerCase().indexOf(s) >= 0);
        if (r) ok = ok && ((it.id || "").toLowerCase().indexOf(r) >= 0);
        return ok;
      });

      var meta = createEl("div", "vsp-section-sub",
        "Total overrides: " + list.length + " / " + filtered.length + " after filters.");
      tableHost.innerHTML = "";
      tableHost.appendChild(meta);

      var table = createEl("table", "vsp-table");
      var thead = document.createElement("thead");
      var trH = document.createElement("tr");
      ["Rule ID", "Tool", "Scope", "Old → New severity", "Reason", "Ticket / Reference"]
        .forEach(function (h) {
          var th = document.createElement("th");
          th.textContent = h;
          trH.appendChild(th);
        });
      thead.appendChild(trH);
      table.appendChild(thead);

      var tbody = document.createElement("tbody");
      if (!filtered.length) {
        var tr = document.createElement("tr");
        var td = document.createElement("td");
        td.colSpan = 6;
        td.textContent = "No overrides for current filters.";
        tr.appendChild(td);
        tbody.appendChild(tr);
      } else {
        filtered.forEach(function (it) {
          var tr = document.createElement("tr");

          function td(txt) {
            var td = document.createElement("td");
            td.textContent = txt || "";
            return td;
          }

          tr.appendChild(td(it.id || ""));
          tr.appendChild(td(it.tool || ""));
          tr.appendChild(td(it.scope || it.scope_type || ""));
          var tdSev = document.createElement("td");
          var old = pillSeverity(it.old_severity || "");
          var arrow = createEl("span", "vsp-text-small", " → ");
          var newS = pillSeverity(it.new_severity || "");
          tdSev.appendChild(old);
          tdSev.appendChild(arrow);
          tdSev.appendChild(newS);
          tr.appendChild(tdSev);
          tr.appendChild(td(it.reason || ""));
          tr.appendChild(td(it.jira || it.ticket || ""));
          tbody.appendChild(tr);
        });
      }
      table.appendChild(tbody);
      tableHost.appendChild(table);
    }

    btnApply.addEventListener("click", apply);
    apply();
  }

  function renderOverrides(inner, state) {
    inner.innerHTML = "";

    var top = createEl("div", "");
    inner.appendChild(top);

    var editorHolder = createEl("div", "vsp-card");
    editorHolder.style.marginTop = "16px";
    var eTitle = createEl("div", "vsp-card-title", "Rule Override Editor");
    var eSub = createEl("div", "vsp-section-sub",
      "JSON preview – not saved yet. Use Validate to check syntax before saving.");
    editorHolder.appendChild(eTitle);
    editorHolder.appendChild(eSub);

    var ta = document.createElement("textarea");
    ta.className = "vsp-textarea";
    ta.style.width = "100%";
    ta.style.minHeight = "260px";
    ta.style.fontFamily = "monospace";
    ta.style.fontSize = "12px";
    ta.value = state.editorText || "[]";
    editorHolder.appendChild(ta);

    var btnRow = createEl("div", "vsp-row");
    btnRow.style.display = "flex";
    btnRow.style.justifyContent = "flex-end";
    btnRow.style.gap = "8px";
    btnRow.style.marginTop = "8px";

    var btnValidate = createEl("button", "vsp-btn-ghost", "Validate JSON");
    var btnSave = createEl("button", "vsp-btn-primary", "Apply & Save");
    btnRow.appendChild(btnValidate);
    btnRow.appendChild(btnSave);
    editorHolder.appendChild(btnRow);

    var status = createEl("div", "vsp-section-sub");
    status.style.marginTop = "4px";
    status.textContent = state.editorStatus || "";
    editorHolder.appendChild(status);

    inner.appendChild(editorHolder);

    // SUMMARY đã được load trong state.summaryList
    renderSummary(top, state.summaryList || []);

    function refreshSummary() {
      fetch("/api/vsp/rule_overrides")
        .then(function (r) { return r.json(); })
        .then(function (data) {
          if (!data.ok) {
            console.error("rule_overrides summary error", data);
            return;
          }
          state.summaryList = data.items || [];
          renderSummary(top, state.summaryList);
        })
        .catch(function (e) {
          console.error("rule_overrides summary error", e);
        });
    }

    btnValidate.addEventListener("click", function () {
      state.editorText = ta.value;
      status.textContent = "Validating…";
      fetch("/api/vsp/rule_overrides_validate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: ta.value })
      })
        .then(function (r) { return r.json().then(function (j) { return { status: r.status, body: j }; }); })
        .then(function (res) {
          if (!res.body.ok) {
            status.textContent = "Invalid: " + (res.body.error || ("HTTP " + res.status));
          } else {
            status.textContent = "Valid JSON. Items: " + (res.body.items || 0) + ".";
          }
        })
        .catch(function (e) {
          console.error(e);
          status.textContent = "Error calling validate API.";
        });
    });

    btnSave.addEventListener("click", function () {
      state.editorText = ta.value;
      status.textContent = "Saving…";
      fetch("/api/vsp/rule_overrides_save", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: ta.value })
      })
        .then(function (r) { return r.json().then(function (j) { return { status: r.status, body: j }; }); })
        .then(function (res) {
          if (!res.body.ok) {
            status.textContent = "Save failed: " + (res.body.error || ("HTTP " + res.status));
          } else {
            status.textContent = "Saved to " + (res.body.path || "") +
              " (items=" + (res.body.items || 0) + ").";
            refreshSummary();
          }
        })
        .catch(function (e) {
          console.error(e);
          status.textContent = "Error calling save API.";
        });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    var ov = createOverlay("overrides");
    var overlay = ov.overlay;
    var inner = ov.inner;

    var state = {
      summaryList: [],
      editorText: "",
      editorStatus: ""
    };

    function hide() { overlay.style.display = "none"; }

    function show() {
      overlay.style.display = "block";
      inner.innerHTML = "<div class='vsp-section-sub'>Loading rule overrides…</div>";

      // Load summary + raw text song song
      Promise.all([
        fetch("/api/vsp/rule_overrides").then(function (r) { return r.json(); }),
        fetch("/api/vsp/rule_overrides_raw").then(function (r) { return r.json(); })
      ])
        .then(function (arr) {
          var summary = arr[0];
          var raw = arr[1];

          if (summary.ok) state.summaryList = summary.items || [];
          else state.summaryList = [];

          if (raw.ok) {
            state.editorText = raw.text || "[]";
            state.editorStatus = "Loaded from " + (raw.path || "");
          } else {
            state.editorText = "[]";
            state.editorStatus = "Cannot load overrides: " + (raw.error || "unknown error");
          }

          renderOverrides(inner, state);
        })
        .catch(function (e) {
          console.error("rule_overrides overlay error", e);
          inner.innerHTML = "<div class='vsp-section-sub'>Error: cannot load rule overrides APIs.</div>";
        });
    }

    ['dashboard', 'runs & reports', 'data source', 'settings'].forEach(function (lbl) {
      var n = findNav(lbl);
      if (n) n.addEventListener("click", function () { setTimeout(hide, 0); });
    });

    var nav = findNav("rule overrides");
    if (nav) nav.addEventListener("click", function () { setTimeout(show, 0); });
  });
})();
