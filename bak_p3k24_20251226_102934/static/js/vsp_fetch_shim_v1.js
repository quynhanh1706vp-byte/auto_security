(function () {
  const LOG = "[VSP_FETCH_SHIM]";
  const ORIG = (window.fetch && window.fetch.bind(window)) || fetch;

  function log(...args) {
    try {
      console.warn(LOG, ...args);
    } catch (e) {}
  }

  window.fetch = function (input, init) {
    let url = (typeof input === "string") ? input : (input && input.url) || "";

    // Chuẩn hóa: chỉ lấy path để so pattern nếu cần
    try {
      const u = new URL(url, window.location.origin);
      url = u.pathname + u.search;
    } catch (e) {
      // nếu không parse được thì dùng nguyên string
    }

    // 1) Legacy bug: /api/vsp/runs_v3?limit=200&offset=0
    if (url.includes("/api/vsp/runs_v3?limit=200&offset=0")) {
      const fixed = url.replace("runs_v3?limit=200&offset=0", "runs_v3?limit=200&offset=0");
      log("redirect runs_v3?limit=200&offset=0 ->", fixed);
      return ORIG(fixed, init);
    }

    // 2) Legacy API: /api/vsp/runs_v2 -> runs_v3?limit=200&offset=0
    if (url.includes("/api/vsp/runs_v2")) {
      const fixed = url.replace("runs_v2", "runs_v3?limit=200&offset=0");
      log("redirect runs_v2 ->", fixed);
      return ORIG(fixed, init);
    }

    // 3) Legacy top_cwe_v1 – stub rỗng, tránh 404
    if (url.includes("/api/vsp/top_cwe_v1")) {
      log("stub top_cwe_v1");
      const body = JSON.stringify({ ok: true, items: [] });
      return Promise.resolve(new Response(body, {
        status: 200,
        headers: { "Content-Type": "application/json" }
      }));
    }

    // 4) Legacy settings/get – stub rỗng, tránh 404
    if (url.includes("/api/vsp/settings/get")) {
      log("stub settings/get");
      const body = JSON.stringify({
        ok: true,
        profiles: [],
        tool_overrides: []
      });
      return Promise.resolve(new Response(body, {
        status: 200,
        headers: { "Content-Type": "application/json" }
      }));
    }

    return ORIG(input, init);
  };

  console.log(LOG, "installed");
})();
