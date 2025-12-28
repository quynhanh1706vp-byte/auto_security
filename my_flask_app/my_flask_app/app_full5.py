from flask import Flask, send_from_directory

# Serve thẳng các file trong thư mục này
app = Flask(
    __name__,
    static_folder=".",
    template_folder="."
)

@app.route("/")
def index():
    # Trang 5 tab chính
    return send_from_directory(".", "SECURITY_BUNDLE_FULL_5_PAGES.html")

@app.route("/ui5")
def ui5():
    # Route phụ, trỏ cùng file cho tiện test
    return send_from_directory(".", "SECURITY_BUNDLE_FULL_5_PAGES.html")

@app.route("/<path:path>")
def static_proxy(path: str):
    # Để nếu HTML có load thêm file JS/CSS cùng thư mục thì vẫn lấy được
    return send_from_directory(".", path)

if __name__ == "__main__":
    # Chạy port 8910
    app.run(host="0.0.0.0", port=8910, debug=False)
