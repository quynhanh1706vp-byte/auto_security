// === VSP 2025 – RUN SCAN NOW Button ===
// Gắn nút vào tab Runs & Reports

document.addEventListener("DOMContentLoaded", function () {
  try {
    const runsHeader = document.querySelector("#vsp-runs-main .vsp-card-header");
    if (!runsHeader) {
      console.warn("[VSP_RUN_BTN] Không tìm thấy header của tab Runs.");
      return;
    }

    // Tránh gắn trùng nút nếu script load lại
    if (runsHeader.querySelector("[data-vsp-run-btn]")) {
      console.log("[VSP_RUN_BTN] Button đã tồn tại, bỏ qua.");
      return;
    }

    // Tạo nút Run Scan Now
    const btn = document.createElement("button");
    btn.textContent = "Run Scan Now";
    btn.className = "vsp-btn";
    btn.dataset.vspRunBtn = "1";
    btn.style.marginLeft = "10px";

    btn.addEventListener("click", function () {
      openRunScanModal();
    });

    runsHeader.appendChild(btn);
    console.log("[VSP_RUN_BTN] Đã gắn nút Run Scan Now vào tab Runs.");
  } catch (e) {
    console.error("[VSP_RUN_BTN] Lỗi khi khởi tạo nút:", e);
  }
});


// === Modal tạo request scan ===
function openRunScanModal() {
  // Nếu đã có modal thì không tạo thêm
  if (document.getElementById("vsp-run-modal")) return;

  const html = `
    <div id="vsp-run-modal" style="
      position: fixed; inset: 0;
      background: rgba(0,0,0,0.6);
      display:flex; align-items:center; justify-content:center;
      z-index: 9999;
    ">
      <div style="
        background:#0b1020; padding:20px; border-radius:12px;
        width:360px; box-shadow:0 0 30px rgba(0,0,0,0.4);
        color:#E5E7EB; font-family:Inter, system-ui, sans-serif;
      ">
        <h3 style="margin:0 0 12px 0; font-size:16px;">Run Scan Now</h3>

        <label style="font-size:12px; color:#9CA3AF;">Profile</label>
        <select id="vsp-run-profile" style="
          width:100%; margin-bottom:12px; padding:6px 10px;
          border-radius:8px; background:#111827; color:white;
          border:1px solid #334155; font-size:12px;
        ">
          <option value="FULL_EXT">FULL_EXT</option>
          <option value="FAST">FAST</option>
        </select>

        <label style="font-size:12px; color:#9CA3AF;">Target Path</label>
        <input id="vsp-run-target" value="/home/test/Data/SECURITY-10-10-v4" style="
          width:100%; margin-bottom:16px; padding:6px 10px;
          border-radius:8px; background:#111827; color:white;
          border:1px solid #334155; font-size:12px;
        " />

        <div style="display:flex; justify-content:flex-end; gap:10px;">
          <button type="button" onclick="closeRunScanModal()" class="vsp-btn-secondary">
            Cancel
          </button>
          <button type="button" onclick="submitRunScan()" class="vsp-btn">
            Run
          </button>
        </div>
      </div>
    </div>
  `;
  document.body.insertAdjacentHTML("beforeend", html);
}

function closeRunScanModal() {
  const m = document.getElementById("vsp-run-modal");
  if (m) m.remove();
}


// === Gửi request scan ===
async function submitRunScan() {
  const profileEl = document.getElementById("vsp-run-profile");
  const targetEl  = document.getElementById("vsp-run-target");

  if (!profileEl || !targetEl) {
    alert("Form không hợp lệ, vui lòng reload trang.");
    return;
  }

  const profile = profileEl.value;
  const target  = targetEl.value.trim();

  if (!target) {
    alert("Vui lòng nhập Target Path.");
    return;
  }

  const payload = {
    mode: "local",
    profile: profile,
    target_type: "path",
    target: target
  };

  try {
    const resp = await fetch("/api/vsp/run", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(payload)
    });

    const data = await resp.json();

    if (data && data.ok) {
      const reqId = data.request_id || "(no id)";
      alert("Scan started!\nRequest ID: " + reqId);
      console.log("[VSP_RUN_BTN] Scan accepted:", data);
      closeRunScanModal();

      // Refresh bảng runs nếu hàm loader tồn tại
      if (window.VSP_RUNS_LOAD_TABLE) {
        setTimeout(() => {
          try {
            window.VSP_RUNS_LOAD_TABLE();
          } catch (e) {
            console.error("[VSP_RUN_BTN] Lỗi khi reload bảng Runs:", e);
          }
        }, 1500);
      }
    } else {
      const msg = (data && (data.error || data.message)) || "unknown error";
      alert("Failed to trigger scan: " + msg);
      console.error("[VSP_RUN_BTN] API trả lỗi:", data);
    }

  } catch (err) {
    alert("Error calling API: " + err);
    console.error("[VSP_RUN_BTN] Exception khi gọi /api/vsp/run:", err);
  }
}
