#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS_DIR="$ROOT/static/js"

echo "[INFO] ROOT = $ROOT"
mkdir -p "$JS_DIR"

########################################
# 1) SETTINGS TAB
########################################
SETTINGS_JS="$JS_DIR/vsp_settings_tab_v1.js"

if [ -f "$SETTINGS_JS" ]; then
  BAK="${SETTINGS_JS}.bak_$(date +%Y%m%d_%H%M%S)"
  cp "$SETTINGS_JS" "$BAK"
  echo "[BACKUP] $SETTINGS_JS -> $BAK"
fi

cat > "$SETTINGS_JS" << 'JS'
(function () {
  const LOG_PREFIX = "[VSP_SETTINGS_TAB]";

  function $(sel, root) {
    return (root || document).querySelector(sel);
  }

  function createEl(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text) el.textContent = text;
    return el;
  }

  function renderSettingsEmpty(root) {
    root.innerHTML = "";
    const card = createEl("div", "vsp-card");
    const title = createEl("div", "vsp-section-title", "Global settings (read-only)");
    const desc = createEl(
      "div",
      "vsp-section-desc",
      "Hiện tại chưa có nhóm cấu hình nào được expose ra UI. Backend vẫn đang hoạt động bình thường. " +
      "Khi anh thêm các nhóm config (ví dụ: bật / tắt tool, ngưỡng severity, mapping CI/CD), tab này sẽ hiển thị chi tiết."
    );
    const empty = createEl(
      "div",
      "vsp-empty",
      "Không có settings nào trong settings_ui_v1. " +
      "Hãy cấu hình file config/settings_v1.json và API /api/vsp/settings_ui_v1 để xem được dữ liệu tại đây."
    );
    card.appendChild(title);
    card.appendChild(desc);
    card.appendChild(empty);
    root.appendChild(card);
  }

  function renderSettingsTable(root, payload) {
    root.innerHTML = "";

    const card = createEl("div", "vsp-card");
    const header = createEl("div", "vsp-main-header");
    const left = createEl("div");
    const title = createEl("div", "vsp-section-title", "Global settings");
    const desc = createEl(
      "div",
      "vsp-section-desc",
      "Các cấu hình core được VSP 2025 đọc từ backend. " +
      "Anh có thể dùng phần này như \"bản in ra\" của config JSON để kiểm tra nhanh."
    );
    left.appendChild(title);
    left.appendChild(desc);
    header.appendChild(left);
    card.appendChild(header);

    const wrap = createEl("div", "vsp-table-wrap");
    const table = createEl("table", "vsp-table");
    const thead = document.createElement("thead");
    const thRow = document.createElement("tr");
    ["Nhóm", "Key", "Giá trị"].forEach((h) => {
      const th = document.createElement("th");
      th.textContent = h;
      thRow.appendChild(th);
    });
    thead.appendChild(thRow);
    table.appendChild(thead);

    const tbody = document.createElement("tbody");

    const settings = payload.settings || {};
    const groupNames = Object.keys(settings).sort();

    if (groupNames.length === 0) {
      // rơi vào case không có group
      wrap.appendChild(table);
      card.appendChild(wrap);
      root.appendChild(card);
      const empty = createEl(
        "div",
        "vsp-empty",
        "settings_ui_v1 trả về ok=true nhưng không có group cấu hình. " +
        "Có thể backend chưa map config cụ thể sang UI payload."
      );
      root.appendChild(empty);
      return;
    }

    groupNames.forEach((group) => {
      const groupCfg = settings[group] || {};
      const keys = Object.keys(groupCfg).sort();
      if (keys.length === 0) {
        const tr = document.createElement("tr");
        const tdGroup = document.createElement("td");
        tdGroup.textContent = group;
        const tdKey = document.createElement("td");
        tdKey.textContent = "(empty)";
        const tdVal = document.createElement("td");
        tdVal.textContent = "";
        tr.appendChild(tdGroup);
        tr.appendChild(tdKey);
        tr.appendChild(tdVal);
        tbody.appendChild(tr);
        return;
      }

      keys.forEach((key, idx) => {
        const tr = document.createElement("tr");
        const tdGroup = document.createElement("td");
        tdGroup.textContent = idx === 0 ? group : "";
        const tdKey = document.createElement("td");
        tdKey.textContent = key;
        const tdVal = document.createElement("td");
        let val = groupCfg[key];
        try {
          if (typeof val === "object") {
            val = JSON.stringify(val);
          }
        } catch (e) {
          // ignore
        }
        tdVal.textContent = String(val);
        tr.appendChild(tdGroup);
        tr.appendChild(tdKey);
        tr.appendChild(tdVal);
        tbody.appendChild(tr);
      });
    });

    table.appendChild(tbody);
    wrap.appendChild(table);
    card.appendChild(wrap);
    root.appendChild(card);
  }

  function loadSettings(root) {
    const container = root || $("#vsp-tab-settings");
    if (!container) {
      console.warn(LOG_PREFIX, "Không tìm thấy #vsp-tab-settings");
      return;
    }

    container.innerHTML = "";
    const loadingCard = createEl("div", "vsp-card");
    loadingCard.textContent = "Đang tải settings từ /api/vsp/settings_ui_v1 ...";
    container.appendChild(loadingCard);

    fetch("/api/vsp/settings_ui_v1")
      .then((res) => res.json())
      .then((data) => {
        console.log(LOG_PREFIX, "settings_ui_v1 payload:", data);
        if (!data || data.ok === false) {
          renderSettingsEmpty(container);
          return;
        }
        const settings = data.settings || {};
        if (Object.keys(settings).length === 0) {
          renderSettingsEmpty(container);
        } else {
          renderSettingsTable(container, data);
        }
      })
      .catch((err) => {
        console.error(LOG_PREFIX, "Lỗi fetch settings_ui_v1:", err);
        const card = createEl("div", "vsp-card");
        card.textContent = "Không tải được settings từ backend. Kiểm tra log server.";
        container.innerHTML = "";
        container.appendChild(card);
      });
  }

  // Hàm global để console patch gọi
  window.vspInitSettingsTab = function (root) {
    console.log(LOG_PREFIX, "Init settings tab");
    loadSettings(root);
  };
})();
JS

########################################
# 2) RULE OVERRIDES TAB
########################################
RO_JS="$JS_DIR/vsp_rule_overrides_tab_v1.js"

if [ -f "$RO_JS" ]; then
  BAK="${RO_JS}.bak_$(date +%Y%m%d_%H%M%S)"
  cp "$RO_JS" "$BAK"
  echo "[BACKUP] $RO_JS -> $BAK"
fi

cat > "$RO_JS" << 'JS'
(function () {
  const LOG_PREFIX = "[VSP_RULE_OVERRIDES_TAB]";

  function $(sel, root) {
    return (root || document).querySelector(sel);
  }

  function createEl(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text) el.textContent = text;
    return el;
  }

  function renderEmpty(root) {
    root.innerHTML = "";
    const card = createEl("div", "vsp-card");
    const title = createEl("div", "vsp-section-title", "Rule overrides");
    const desc = createEl(
      "div",
      "vsp-section-desc",
      "Danh sách rule override đang trống hoặc backend chưa map dữ liệu UI. " +
      "Tab này dùng để quan sát các rule đã được giảm mức độ, suppress hoặc annotate."
    );
    const empty = createEl(
      "div",
      "vsp-empty",
      "Không có rule override nào được trả về từ /api/vsp/rule_overrides_ui_v1."
    );
    card.appendChild(title);
    card.appendChild(desc);
    card.appendChild(empty);
    root.appendChild(card);
  }

  function renderTable(root, items) {
    root.innerHTML = "";

    const card = createEl("div", "vsp-card");
    const header = createEl("div", "vsp-main-header");
    const left = createEl("div");
    const title = createEl("div", "vsp-section-title", "Rule overrides");
    const desc = createEl(
      "div",
      "vsp-section-desc",
      "Danh sách các rule đã được override (ví dụ: đổi severity, suppress, thêm ghi chú). " +
      "Chế độ hiện tại là read-only để kiểm soát governance."
    );
    left.appendChild(title);
    left.appendChild(desc);
    header.appendChild(left);
    card.appendChild(header);

    const toolbar = createEl("div", "vsp-toolbar");
    const tbLeft = createEl("div", "vsp-toolbar-left");
    const search = createEl("input", "vsp-input");
    search.type = "text";
    search.placeholder = "Tìm theo tool, rule_id, pattern...";
    tbLeft.appendChild(search);
    toolbar.appendChild(tbLeft);
    card.appendChild(toolbar);

    const wrap = createEl("div", "vsp-table-wrap");
    const table = createEl("table", "vsp-table");
    const thead = document.createElement("thead");
    const trHead = document.createElement("tr");
    ["Tool", "Rule ID", "Pattern", "Action", "Severity", "Note"].forEach((h) => {
      const th = document.createElement("th");
      th.textContent = h;
      trHead.appendChild(th);
    });
    thead.appendChild(trHead);
    table.appendChild(thead);

    const tbody = document.createElement("tbody");

    function matchesFilter(item, q) {
      if (!q) return true;
      q = q.toLowerCase();
      const fields = [
        item.tool || "",
        item.rule_id || "",
        item.pattern || "",
        item.action || "",
        item.note || "",
        item.severity || "",
      ];
      return fields.some((f) => String(f).toLowerCase().includes(q));
    }

    function renderRows(q) {
      tbody.innerHTML = "";
      const filtered = items.filter((it) => matchesFilter(it, q));
      if (filtered.length === 0) {
        const tr = document.createElement("tr");
        const td = document.createElement("td");
        td.colSpan = 6;
        td.textContent = "Không có rule override nào match filter hiện tại.";
        tr.appendChild(td);
        tbody.appendChild(tr);
        return;
      }
      filtered.forEach((it) => {
        const tr = document.createElement("tr");

        const tdTool = document.createElement("td");
        tdTool.textContent = it.tool || "";
        const tdRule = document.createElement("td");
        tdRule.textContent = it.rule_id || "";
        const tdPattern = document.createElement("td");
        tdPattern.textContent = it.pattern || "";
        const tdAction = document.createElement("td");
        tdAction.textContent = it.action || "";
        const tdSev = document.createElement("td");
        const sev = it.severity || "";
        const sevSpan = createEl("span", "vsp-badge");
        sevSpan.setAttribute("data-severity", String(sev).toUpperCase());
        sevSpan.textContent = sev || "—";
        tdSev.appendChild(sevSpan);
        const tdNote = document.createElement("td");
        tdNote.textContent = it.note || "";

        tr.appendChild(tdTool);
        tr.appendChild(tdRule);
        tr.appendChild(tdPattern);
        tr.appendChild(tdAction);
        tr.appendChild(tdSev);
        tr.appendChild(tdNote);

        tbody.appendChild(tr);
      });
    }

    renderRows("");

    table.appendChild(tbody);
    wrap.appendChild(table);
    card.appendChild(wrap);
    root.appendChild(card);

    search.addEventListener("input", () => {
      renderRows(search.value || "");
    });
  }

  function loadRuleOverrides(root) {
    const container = root || $("#vsp-tab-rule-overrides");
    if (!container) {
      console.warn(LOG_PREFIX, "Không tìm thấy #vsp-tab-rule-overrides");
      return;
    }

    container.innerHTML = "";
    const loadingCard = createEl("div", "vsp-card");
    loadingCard.textContent = "Đang tải rule overrides từ /api/vsp/rule_overrides_ui_v1 ...";
    container.appendChild(loadingCard);

    fetch("/api/vsp/rule_overrides_ui_v1")
      .then((res) => res.json())
      .then((data) => {
        console.log(LOG_PREFIX, "rule_overrides_ui_v1 payload:", data);
        const items = (data && data.items) || data || [];
        if (!items || (Array.isArray(items) && items.length === 0)) {
          renderEmpty(container);
        } else if (Array.isArray(items)) {
          renderTable(container, items);
        } else if (items.items && Array.isArray(items.items)) {
          renderTable(container, items.items);
        } else {
          renderEmpty(container);
        }
      })
      .catch((err) => {
        console.error(LOG_PREFIX, "Lỗi fetch rule_overrides_ui_v1:", err);
        const card = createEl("div", "vsp-card");
        card.textContent = "Không tải được rule overrides từ backend. Kiểm tra log server.";
        container.innerHTML = "";
        container.appendChild(card);
      });
  }

  // Hàm global – nếu console patch có gọi thì sẽ hoạt động
  window.vspInitRuleOverridesTab = function (root) {
    console.log(LOG_PREFIX, "Init rule overrides tab");
    loadRuleOverrides(root);
  };
})();
JS

echo "[DONE] patch_vsp_settings_rule_tabs_v1.sh hoàn tất."
