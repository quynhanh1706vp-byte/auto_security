document.addEventListener("DOMContentLoaded", function () {
  const pre = document.getElementById("tool-config-json");
  const tbody = document.getElementById("tool-config-body");
  if (!pre || !tbody) {
    return;
  }

  let text = pre.textContent || pre.innerText || "";
  text = text.trim();
  if (!text) {
    return;
  }

  let data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    console.warn("[Settings] Không parse được tool_config JSON:", e);
    return;
  }

  // tool_config.json có thể là list hoặc object có key "tools"
  let tools = [];
  if (Array.isArray(data)) {
    tools = data;
  } else if (Array.isArray(data.tools)) {
    tools = data.tools;
  } else if (data.tools && typeof data.tools === "object") {
    tools = Object.values(data.tools);
  }

  tbody.innerHTML = "";
  if (!tools.length) {
    const tr = document.createElement("tr");
    const td = document.createElement("td");
    td.colSpan = 5;
    td.textContent = "No tool configuration loaded.";
    tr.appendChild(td);
    tbody.appendChild(tr);
    return;
  }

  tools.forEach((t) => {
    const tr = document.createElement("tr");

    const tdTool = document.createElement("td");
    tdTool.textContent = t.tool || t.name || "-";
    tr.appendChild(tdTool);

    const tdEnabled = document.createElement("td");
    const en = !!(t.enabled ?? t.enable ?? t.on);
    tdEnabled.textContent = en ? "ON" : "OFF";
    tdEnabled.classList.add(en ? "status-ok" : "status-off");
    tr.appendChild(tdEnabled);

    const tdLevel = document.createElement("td");
    tdLevel.textContent = t.level || t.profile || "-";
    tr.appendChild(tdLevel);

    const tdModes = document.createElement("td");
    let modes = t.modes || t.mode || t.available_modes || [];
    if (typeof modes === "string") {
      modes = [modes];
    }
    if (!Array.isArray(modes)) {
      modes = [];
    }
    tdModes.textContent = modes.join(", ");
    tr.appendChild(tdModes);

    const tdNote = document.createElement("td");
    tdNote.textContent = t.note || t.notes || t.description || "";
    tr.appendChild(tdNote);

    tbody.appendChild(tr);
  });
});
