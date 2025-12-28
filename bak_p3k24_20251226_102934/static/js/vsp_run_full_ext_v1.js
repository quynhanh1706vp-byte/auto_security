// === VSP RUN FULL EXT+ – FIX V2 ===

console.log("[VSP_RUN][FULL_EXT] vsp_run_full_ext_v1.js loaded");

function vspGetRunSrc() {
  // Thử lần lượt vài ID phổ biến trong TAB 4
  let el =
    document.querySelector("#vsp_run_full_src") ||
    document.querySelector("#vsp_run_src") ||
    document.querySelector("#vsp_run_full_src_path") ||
    document.querySelector("#trigger_full_src");

  if (!el) {
    console.warn("[VSP_RUN][FULL_EXT] Không tìm thấy input SRC trong DOM");
    return "";
  }
  return (el.value || "").trim();
}

function vspRunFullExtFromUI() {
  const src = vspGetRunSrc();

  if (!src) {
    alert("Hãy nhập SRC path trước khi chạy FULL EXT+.");
    return;
  }

  console.log("[VSP_RUN][FULL_EXT] Gửi run_full_ext với src =", src);

  fetch("/api/vsp/run_full_ext", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ src: src })
  })
    .then(async (resp) => {
      const text = await resp.text();
      let data = null;
      try {
        data = JSON.parse(text);
      } catch (e) {
        console.warn("[VSP_RUN][FULL_EXT] Body không phải JSON thuần:", text);
      }

      console.log(
        "[VSP_RUN][FULL_EXT] Response",
        "status=", resp.status,
        "data=", data || text
      );

      if (!resp.ok || !data || data.ok === false) {
        const msg = (data && data.error) || text || ("HTTP " + resp.status);
        alert("Run FULL EXT+ FAILED: " + msg);
        return;
      }

      alert("Run FULL EXT+ STARTED: " + (data.run_id || "OK"));
    })
    .catch((err) => {
      console.error("[VSP_RUN][FULL_EXT] Fetch error", err);
      alert("Run FULL EXT+ error (xem console).");
    });
}

// bind nút "Run now"
document.addEventListener("DOMContentLoaded", function () {
  const btn =
    document.querySelector("#vsp_run_full_btn") ||
    document.querySelector("#trigger_full_run_btn");

  if (!btn) {
    console.warn("[VSP_RUN][FULL_EXT] Không tìm thấy button Run now trong DOM");
    return;
  }

  btn.addEventListener("click", function (ev) {
    ev.preventDefault();
    vspRunFullExtFromUI();
  });
});
