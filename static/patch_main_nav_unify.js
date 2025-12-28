(function () {
  function normalize(path) {
    if (!path) return "/";
    try {
      if (path.startsWith("http://") || path.startsWith("https://")) {
        path = new URL(path).pathname || "/";
      }
    } catch (e) {}
    if (!path.startsWith("/")) path = "/" + path;
    if (path.length > 1 && path.endsWith("/")) path = path.slice(0, -1);
    return path;
  }

  document.addEventListener("DOMContentLoaded", function () {
    try {
      var sidebar = document.querySelector(".sb-sidebar");
      if (!sidebar) return;

      // Menu CHUẨN: 5 tab, route thật của Rule overrides là /tool_rules
      var defs = [
        { href: "/",           label: "Dashboard" },
        { href: "/runs",       label: "Runs & Reports" },
        { href: "/settings",   label: "Settings" },
        { href: "/datasource", label: "Data Source" },
        { href: "/tool_rules", label: "Rule overrides" }
      ];

      // Tìm container chứa nav
      var container =
        sidebar.querySelector(".sb-nav") ||
        sidebar.querySelector(".sb-menu") ||
        sidebar.querySelector("nav") ||
        sidebar;

      var items = Array.from(container.querySelectorAll(".nav-item"));

      // Nếu chưa có .nav-item nào, wrap các <a> sẵn có thành .nav-item
      if (!items.length) {
        var links = Array.from(container.querySelectorAll("a[href^='/']"));
        if (links.length) {
          container.innerHTML = "";
          links.forEach(function (link) {
            var item = document.createElement("div");
            item.className = "nav-item";
            item.appendChild(link);
            container.appendChild(item);
          });
          items = Array.from(container.querySelectorAll(".nav-item"));
        }
      }

      if (!items.length) return;

      var parent = items[0].parentElement || container;

      // Đảm bảo có đủ 5 item
      for (var i = items.length; i < defs.length; i++) {
        var item = document.createElement("div");
        item.className = "nav-item";
        var a = document.createElement("a");
        item.appendChild(a);
        parent.appendChild(item);
        items.push(item);
      }

      // Ánh xạ defs vào từng item
      items.forEach(function (item, idx) {
        var def = defs[idx];
        var a = item.querySelector("a") || (function () {
          var link = document.createElement("a");
          item.appendChild(link);
          return link;
        })();

        if (!def) {
          // Thừa item thì ẩn đi
          item.style.display = "none";
          return;
        }

        a.setAttribute("href", def.href);
        a.textContent = def.label;
      });

      // Active: xóa hết rồi set đúng 1 tab theo URL hiện tại
      var current = normalize(window.location.pathname);
      items.forEach(function (item) {
        item.classList.remove("active");
      });

      defs.forEach(function (def, idx) {
        if (normalize(def.href) === current && items[idx]) {
          items[idx].classList.add("active");
        }
      });

      console.log("[patch_main_nav_unify] unified for", current);
    } catch (e) {
      console.warn("[patch_main_nav_unify] error:", e);
    }
  });
})();
