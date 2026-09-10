#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
ChatLaw 内嵌 Python 服务入口（Android serious_python / 桌面均可运行）。

架构：
  Flutter(Dart) ──HTTP──▶ main.py（本进程内嵌 Python，127.0.0.1:18765）
                          ├─ /health  服务就绪探测
                          ├─ /rag      设 RAG_QUERY → rag.main() → 返回检索条文
                          ├─ /build    build.main()（读 rag_result.json → prompt.txt）
                          └─ /tokenize tokenize.main()（读 prompt.txt → model_inputs.pkl）

- 资源根：启动时设置环境变量 APPDATA_DIR = <app根>/resources（本文件同级 resources/），
  与各 python 模块的 _get_resources_path() 约定一致；外部也可用真实环境变量覆盖。
- 只依赖 Python 标准库（http.server），不引入任何第三方包。
- 桌面烟雾测试：python main.py --port 18765，然后 curl -X POST .../rag。

打包形态（serious_python）：本文件与 python/ 包、resources/ 一起作为 app 目录
（见 docs/client_modules.md §6），经 serious_python:main package 打入 app.zip。
"""

import argparse
import json
import os
import sys
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Dart 侧 lib/services/chat_pipeline.dart 中的 kPythonServicePort 与此保持一致
DEFAULT_PORT = 18765

# 应用根目录推导（按可靠度从高到低）：
#   1) 正常 CLI / 桌面子进程：__file__ 存在，基于它推导；
#   2) serious_python 嵌入执行：顶层脚本没有 __file__，且 cwd 被切到数据目录
#      （files/data），不能用 cwd。此时 `python/` 包在 app 目录内且可被导入，
#      用 python.__file__ 反推 app 根（resources/ 与 python/ 同级）；
#   3) 兜底：os.getcwd()。
if "__file__" in globals():
    _APP_ROOT = os.path.dirname(os.path.abspath(__file__))
else:
    _APP_ROOT = None
    try:
        import python  # noqa: F401  包命名空间（勿顶层化），仅取路径
        _APP_ROOT = os.path.dirname(
            os.path.dirname(os.path.abspath(python.__file__))
        )
    except Exception:  # noqa: BLE001 —— import 失败时回退 cwd
        _APP_ROOT = os.path.abspath(os.getcwd())
_RESOURCES_DIR = os.path.join(_APP_ROOT, "resources")
print(f"[chatlaw-python] app root = {_APP_ROOT}")
print(f"[chatlaw-python] resources dir = {_RESOURCES_DIR}  exists={os.path.isdir(_RESOURCES_DIR)}")

# serious_python 用 zipimport 提供 site-packages（sitepackages.zip 作为 sys.path 项），
# 但 transformers 等"路径敏感"包会在导入时按真实目录访问其子目录（如
# transformers/models），zip 形式下会抛 NotADirectoryError。此处把 sitepackages.zip
# 一次性解包到真实目录并置于 sys.path 首位（按文件 mtime 缓存，仅首次/重装时执行）。
#
# 额外处理 tokenizers：serious_python 从 pypi.flet.dev 拉到的 tokenizers 原生库
# （lib/arm64/libtokenizers-tokenizers.so）按 cp312 编译、依赖 libpython3.12.so，
# 与本环境内嵌的 Python 3.14 不兼容，一旦 transformers 通过 find_spec("tokenizers")
# 判定"可用"就会加载该原生库并 dlopen 失败。所以这里把 tokenizers 排除在解包外，
# 并把 zip 形式的 site-packages 从 sys.path 去掉，使 transformers 回退到纯 Python
# 慢速分词器（use_fast=False 亦可，二者叠加确保兼容）。langchain 与慢速 tokenizer
# 顶层都不强制 import tokenizers，移除后其余模块仍可正常加载。
_FD = os.path.dirname(_APP_ROOT)
_SITE_ZIP = os.path.join(_FD, "sitepackages.zip")
_SITE_EXTRACT = os.path.join(_FD, "site_extract")


def _install_tokenizers_stub():
    """把打包的纯 Python stub tokenizers 覆盖到 site_extract/tokenizers。

    serious_python 拉到的 tokenizers 原生库在 wheel 中标记 cp39-abi3，但实际动态链接
    依赖 libpython3.12.so，与本环境内嵌的 Python 3.14 不兼容，一旦真实 import（经由
    transformers 的 ggml/convert_slow_tokenizer 等无条件 `from tokenizers import ...`）
    就会 dlopen 失败。我们以 `python/_tokenizers_stub` 作为纯 Python 桩覆盖之，使
    transformers 能完成加载；真正的分词走 transformers 慢速分词器（use_fast=False），
    不依赖 tokenizers 的真实能力。
    """
    try:
        import shutil
        from python import _tokenizers_stub as stub  # 包命名空间（勿顶层化）

        stub_dir = os.path.dirname(os.path.abspath(stub.__file__))
        target = os.path.join(_SITE_EXTRACT, "tokenizers")
        if not os.path.isdir(_SITE_EXTRACT):
            return
        if os.path.isdir(target):
            shutil.rmtree(target, ignore_errors=True)
        shutil.copytree(stub_dir, target)
        # 确保没有原生 .so 被误带
        for root, _dirs, files in os.walk(target):
            for fn in files:
                if fn.endswith(".so"):
                    os.remove(os.path.join(root, fn))
        # 从模块缓存摘除可能已被加载的 tokenizers
        sys.modules.pop("tokenizers", None)
        sys.modules.pop("tokenizers.decoders", None)
        sys.modules.pop("tokenizers.models", None)
        sys.modules.pop("tokenizers.normalizers", None)
        sys.modules.pop("tokenizers.pre_tokenizers", None)
        sys.modules.pop("tokenizers.processors", None)
        sys.modules.pop("tokenizers.trainers", None)
        sys.modules.pop("tokenizers.implementations", None)
    except Exception as e:  # noqa: BLE001
        print(f"[chatlaw-python] tokenizers stub 安装失败: {type(e).__name__}: {e}", file=sys.stderr)


def _ensure_site_zip_unpacked():
    if not os.path.isfile(_SITE_ZIP):
        return
    try:
        import shutil
        import zipfile
        mtime = str(int(os.path.getmtime(_SITE_ZIP)))
        marker = os.path.join(_SITE_EXTRACT, ".site_extract_key")
        up_to_date = (
            os.path.isdir(_SITE_EXTRACT)
            and os.path.isfile(marker)
            and open(marker, encoding="utf-8").read().strip() == mtime
        )
        if not up_to_date:
            if os.path.isdir(_SITE_EXTRACT):
                shutil.rmtree(_SITE_EXTRACT, ignore_errors=True)
            os.makedirs(_SITE_EXTRACT, exist_ok=True)
            with zipfile.ZipFile(_SITE_ZIP) as zf:
                # 完整解包（含 tokenizers，后续用 stub 覆盖其原生部分）
                zf.extractall(_SITE_EXTRACT)
            with open(marker, "w", encoding="utf-8") as f:
                f.write(mtime)
        # 只保留解包后的真实目录作为 site-packages 来源，并移除 zip 形式（含原生 .so）。
        sys.path[:] = [
            p for p in sys.path
            if not (p.endswith(".zip") and "sitepackages" in p)
        ]
        if _SITE_EXTRACT not in sys.path:
            sys.path.insert(0, _SITE_EXTRACT)
        # 用纯 Python 桩替换原生 tokenizers，避免 dlopen libpython3.12.so 崩溃。
        _install_tokenizers_stub()
    except Exception as e:  # noqa: BLE001 —— 解包失败不阻断，交给后续 import 报错
        print(f"[chatlaw-python] sitepackages 解包失败: {type(e).__name__}: {e}", file=sys.stderr)


_ensure_site_zip_unpacked()

# 模块懒加载：先把 HTTP 服务跑起来（首次启动资源解包/依赖导入可能较慢），
# 首次请求时才 import 流水线模块，失败则把错误落盘并返回给 Dart。
_rag = _build = _tokenize = None
_error_log_path = None


def _log_error(tag, exc):
    """把启动/请求异常写入 {APPDATA}/pipeline/python_error.log，便于 adb 排查。"""
    try:
        pipeline_dir = os.path.join(os.environ.get("APPDATA_DIR", ""), "pipeline")
        if not os.path.isdir(pipeline_dir):
            os.makedirs(pipeline_dir, exist_ok=True)
        path = os.path.join(pipeline_dir, "python_error.log")
        with open(path, "a", encoding="utf-8") as f:
            f.write(f"[{tag}] {type(exc).__name__}: {exc}\n{traceback.format_exc()}\n")
    except Exception:  # noqa: BLE001 日志失败不影响主流程
        pass


def _get_modules():
    """首次请求时加载 python 包内模块；失败信息可读可查。"""
    global _rag, _build, _tokenize
    if _rag is None:
        # 包命名空间导入，避免 tokenize 遮蔽标准库。
        # 依赖在打包阶段经 pip 装入 site-packages；桌面直跑需先安装 python/requirements.txt。
        from python import rag, build, tokenize

        _rag, _build, _tokenize = rag, build, tokenize
    return _rag, _build, _tokenize


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # 静默访问日志
        pass

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b"{}"
        return json.loads(body.decode("utf-8") or "{}")

    def _send(self, code, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _run(self, fn):
        """执行流水线调用并统一返回 JSON；异常落盘并返回 {ok:false, error}。

        兼容返回值非 dict 的情况（如 build.main() 返回 prompt 字符串、
        tokenize.main() 返回 model_inputs 字符串/bytes）：dict 展开进 payload，
        其它值放入 result 字段，避免 `**(非dict)` 抛 TypeError。
        """
        try:
            out = fn()
            if isinstance(out, dict):
                payload = {"ok": True, **out}
            else:
                payload = {"ok": True, "result": out}
            return self._send(200, payload)
        except Exception as e:  # noqa: BLE001 —— 需把任何失败反馈给 Dart
            _log_error("request", e)
            return self._send(200, {"ok": False, "error": f"{type(e).__name__}: {e}"})

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"ok": True, "ready": True})
        return self._send(404, {"ok": False, "error": f"未知端点 {self.path}"})

    def do_POST(self):
        payload = self._read_json()

        if self.path == "/rag":
            question = payload.get("question", "")
            if not question:
                return self._send(200, {"ok": False, "error": "缺少 question 字段"})

            def run():
                rag, _build, _tokenize = _get_modules()
                os.environ["RAG_QUERY"] = question
                rag.main()
                # rag.main() 会把归一化结果写入 pipeline/rag_result.json，直接回读返回
                result_path = os.path.join(
                    os.environ["APPDATA_DIR"], "pipeline", "rag_result.json"
                )
                with open(result_path, encoding="utf-8") as f:
                    data = json.load(f)
                return {"docs": data.get("results", [])}

            return self._run(run)

        if self.path == "/build":
            # build.main() 返回 prompt 字符串，文件链已落盘 prompt.txt；只返回步骤标识。
            _get_modules()[1].main()
            return self._send(200, {"ok": True, "step": "build"})

        if self.path == "/tokenize":
            # tokenize.main() 返回 BatchEncoding（含 numpy 张量），不可 JSON 序列化；
            # 产物已写盘 model_inputs.pkl，HTTP 仅返回步骤标识。
            _get_modules()[2].main()
            return self._send(200, {"ok": True, "step": "tokenize"})

        return self._send(404, {"ok": False, "error": f"未知端点 {self.path}"})


def main():
    parser = argparse.ArgumentParser(description="ChatLaw 内嵌 Python 服务")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()

    # 资源根：外部（serious_python 环境变量）优先，否则用打包的 resources/
    os.environ.setdefault("APPDATA_DIR", _RESOURCES_DIR)
    print(f"[chatlaw-python] APPDATA_DIR = {os.environ['APPDATA_DIR']}")

    server = ThreadingHTTPServer(("127.0.0.1", args.port), _Handler)
    print(f"[chatlaw-python] 服务已启动: http://127.0.0.1:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
