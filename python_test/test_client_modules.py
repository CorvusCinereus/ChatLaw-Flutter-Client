#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
ChatLaw 客户端 4 个独立模块（asr / rag / build / tokenize）测试脚本

测试对象（位于 ../python/ 下，自包含实现，不依赖原 ChatLaw 仓库）：
    python/asr.py       语音转文字模块（入口 asr.run，输出 pipeline/asr_result.txt）
    python/rag.py       知识库检索模块（入口 rag.main，环境变量 RAG_QUERY，输出 pipeline/rag_result.json）
    python/build.py     Prompt 构建模块（入口 build.main，读 rag_result.json，输出 pipeline/prompt.txt）
    python/tokenize.py  分词模块（入口 tokenize.main，读 prompt.txt，输出 pipeline/model_inputs.pkl）

用法：
    conda activate ChatLaw_env
    cd chatlaw-flutter-client
    python python_test/test_client_modules.py

设计说明：
    1. 模块导入测试：确认 4 个模块可正常 import，且 import 不触发资源下载。
    2. 懒加载验证：import 之后各模块资源缓存必须仍为空（None）。
    3. 纯逻辑测试：法条解析、规范化、去重等不依赖资源的部分。
    4. mock 全链路测试：替换各模块内部 `_get_*()` 懒加载函数为假资源，
       直接走真实 main()/run() 入口，验证入口编排、文件链输出与整条处理链路。
    5. 真实资源端到端测试（条件执行）：若 resources/ 下已存在对应资源，
       则直接调用 rag.main() / tokenize.main() 做真实检索/分词；缺失则显式 SKIP。
"""

import os
import sys
import time
import json
import types
import shutil
import pickle
import tempfile

REPO_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
)
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

# python/ 为包（含 __init__.py），模块以 python.xxx 命名空间导入，
# 避免 asr/rag/build/tokenize 等顶层模块名遮蔽标准库（如 tokenize）。
PYTHON_DIR = os.path.join(REPO_ROOT, "python")
# 资源根目录：优先读取环境变量 APPDATA_DIR（由宿主 APP 传入），
# 未设置时回退到仓库内 resources/（与各模块 _get_resources_path 保持一致）。
RESOURCES_DIR = os.getenv("APPDATA_DIR") or os.path.join(REPO_ROOT, "resources")
# 流水线输出子目录及各环节产物
PIPELINE_DIR = os.path.join(RESOURCES_DIR, "pipeline")
RAG_JSON = os.path.join(PIPELINE_DIR, "rag_result.json")
PROMPT_TXT = os.path.join(PIPELINE_DIR, "prompt.txt")
ASR_TXT = os.path.join(PIPELINE_DIR, "asr_result.txt")
MODEL_INPUTS_PKL = os.path.join(PIPELINE_DIR, "model_inputs.pkl")

# ============================================================
# 极简测试框架：显式 PASS / FAIL / SKIP 输出
# ============================================================
_PASS = 0
_FAIL = 0
_SKIP = 0


def section(title):
    """打印分区标题。"""
    print(f"\n{'=' * 66}\n{title}\n{'=' * 66}")


def check(name, cond, detail=""):
    """断言一项测试并输出 [PASS] / [FAIL]。返回结果供调用方使用。"""
    global _PASS, _FAIL
    if cond:
        _PASS += 1
    else:
        _FAIL += 1
    tag = "PASS" if cond else "FAIL"
    suffix = f"  -> {detail}" if detail else ""
    print(f"  [{tag}] {name}{suffix}")
    return cond


def skip(name, reason):
    """输出 [SKIP] 项（资源缺失等非失败情形，不计入失败）。"""
    global _SKIP
    _SKIP += 1
    print(f"  [SKIP] {name}  -> {reason}")


def cleanup_pipeline():
    """清理流水线输出目录（不保留测试产物）。"""
    if os.path.isdir(PIPELINE_DIR):
        shutil.rmtree(PIPELINE_DIR, ignore_errors=True)


# ============================================================
# 0. 环境信息
# ============================================================
section("0. 环境信息")
print(f"  Python 解释器: {sys.executable}")
print(f"  Python 版本  : {sys.version.split()[0]}")
print(f"  python 模块目录: {PYTHON_DIR}")
print(f"  资源目录      : {RESOURCES_DIR}")
print(f"  APPDATA_DIR   : {os.getenv('APPDATA_DIR') or '（未设置，使用回退路径）'}")
print(f"  流水线目录    : {PIPELINE_DIR}")

# ============================================================
# 1. 模块导入
# ============================================================
section("1. 模块导入（import 不应触发任何资源下载/加载）")
t0 = time.time()
_import_ok = True
try:
    from python import asr
    check("asr 模块", True, f"asr.run = {asr.run}")
except Exception as e:
    _import_ok = False
    check("asr 模块", False, repr(e))
try:
    from python import rag
    check("rag 模块", True, f"rag.main = {rag.main}")
except Exception as e:
    _import_ok = False
    check("rag 模块", False, repr(e))
try:
    from python import build
    check("build 模块", True, f"build.main = {build.main}")
except Exception as e:
    _import_ok = False
    check("build 模块", False, repr(e))
try:
    from python import tokenize
    check("tokenize 模块", True, f"tokenize.main = {tokenize.main}")
except Exception as e:
    _import_ok = False
    check("tokenize 模块", False, repr(e))

print(f"  导入耗时: {time.time() - t0:.2f}s")
if not _import_ok:
    print("\n导入失败，后续测试无法继续。请确认已安装依赖并激活 ChatLaw_env。")
    sys.exit(1)

# ============================================================
# 2. 懒加载验证
# ============================================================
section("2. 懒加载验证（import 后资源缓存必须为空）")
check("rag._vectorstore is None", rag._vectorstore is None)
check("rag._exact_index is None", rag._exact_index is None)
check("rag._law_name_candidates is None", rag._law_name_candidates is None)
check("asr._audio_model is None", asr._audio_model is None)
check("tokenize._tokenizer is None", tokenize._tokenizer is None)

# ============================================================
# 3. rag 法条解析纯逻辑
# ============================================================
section("3. rag 法条解析纯逻辑")
r = rag.normalize_law_name("中华人民共和国公司法_20231229")
check("normalize_law_name 去前缀去日期", r == "公司法", f"got {r!r}")
r = rag.normalize_law_name("《民法典》")
check("normalize_law_name 去书名号", r == "民法典", f"got {r!r}")
r = rag.normalize_article_number(" 第五十八条 ")
check("normalize_article_number 去空白", r == "第五十八条", f"got {r!r}")
law, art = rag.parse_law_article_query("公司法第五十八条的内容是什么？", ["公司法", "民法典"])
check("parse_law_article_query 精确解析", (law, art) == ("公司法", "第五十八条"), f"got ({law}, {art})")
law2, art2 = rag.parse_law_article_query("什么是正当防卫？")
check("parse_law_article_query 无关问题", law2 is None and art2 is None, f"got ({law2}, {art2})")

# ============================================================
# 4. rag.main 混合检索链路 + 自动保存 JSON（mock 资源）
# ============================================================
section("4. rag.main 混合检索链路 + 自动保存 JSON（mock 资源）")


class FakeVS:
    """模拟 FAISS 向量库：similarity_search 返回 k 条带 metadata 的假文档。"""

    def __init__(self):
        self.calls = []

    def similarity_search(self, query, k):
        self.calls.append(k)
        return [
            types.SimpleNamespace(
                page_content=f"法律名称：民法典\n法律简称：民法典\n条号：补充第{i}条\n正文：faiss 参考条文 {i}",
                metadata={
                    "law_name_raw": "民法典",
                    "law_name_norm": "民法典",
                    "article": f"补充第{i}条",
                    "content": f"faiss 参考条文 {i}",
                },
            )
            for i in range(k)
        ]


fake_exact_index = {
    "公司法::第五十八条": {
        "law_name_raw": "中华人民共和国公司法", "law_name_norm": "公司法",
        "article": "第五十八条", "content": "公司应当依法经营。",
    }
}
fake_candidates = ["公司法", "民法典"]

_orig_rag_res = rag._get_resources
_orig_env = os.environ.get("RAG_QUERY")


def _fake_rag_resources():
    return FakeVS(), fake_exact_index, fake_candidates


rag._get_resources = _fake_rag_resources
try:
    # ---- 精确命中场景 ----
    os.environ["RAG_QUERY"] = "公司法第五十八条的内容是什么？"
    docs = rag.main()
    check("main 返回 2 条（1 精确 + 1 补充）", len(docs) == 2, f"len={len(docs)}")
    check("首条为精确命中条文", docs[0]["article"] == "第五十八条", f"got {docs[0]['article']!r}")

    try:
        with open(RAG_JSON, "r", encoding="utf-8") as f:
            p1 = json.load(f)
        check("rag_result.json 生成于 pipeline/ 且可解析", True, RAG_JSON)
        check("JSON 含元信息键", all(k in p1 for k in ("query", "timestamp", "total", "results")),
              f"keys={list(p1.keys())}")
        check("total 与 results 数量一致", p1["total"] == len(p1["results"]), f"total={p1['total']}")
        check("查询词写入正确", p1["query"] == "公司法第五十八条的内容是什么？", f"got {p1['query']!r}")
        keys_ok = all(
            all(k in r for k in ("law_name", "article", "content", "source"))
            for r in p1["results"]
        )
        check("每条结果含统一字段", keys_ok)
        srcs = {r["source"] for r in p1["results"]}
        check("精确命中场景含 exact+faiss 两种来源", srcs == {"exact", "faiss"}, f"got {srcs}")
    except Exception as e:
        check("rag_result.json 精确命中校验", False, repr(e))

    # ---- 未命中场景 + 覆盖验证 ----
    os.environ["RAG_QUERY"] = "随便一个开放性问题"
    docs2 = rag.main()
    check("未命中直接返回 faiss 5 条", len(docs2) == 5, f"len={len(docs2)}")

    try:
        with open(RAG_JSON, "r", encoding="utf-8") as f:
            p2 = json.load(f)
        check("JSON 被覆盖为最新查询", p2["query"] == "随便一个开放性问题" and p2["total"] == 5,
              f"query={p2['query']!r} total={p2['total']}")
        check("未命中场景 source 均为 faiss", {r["source"] for r in p2["results"]} == {"faiss"})
    except Exception as e:
        check("rag_result.json 覆盖校验", False, repr(e))
finally:
    rag._get_resources = _orig_rag_res
    if _orig_env is None:
        os.environ.pop("RAG_QUERY", None)
    else:
        os.environ["RAG_QUERY"] = _orig_env
    cleanup_pipeline()

# ============================================================
# 4b. rag._OnnxEmbeddings（onnxruntime 向量嵌入，无 torch）
# ============================================================
section("4b. rag._OnnxEmbeddings（onnxruntime 向量嵌入）")
import numpy as np
import onnx
import onnx.helper as oh
import onnxruntime as ort

# 构造微型 ONNX 模型：output = cast(attention_mask)（形状 [1, seq]）
tiny_onnx = os.path.join(tempfile.gettempdir(), "tiny_embed_test.onnx")
in_ids = oh.make_tensor_value_info("input_ids", onnx.TensorProto.INT64, [1, "seq"])
in_mask = oh.make_tensor_value_info("attention_mask", onnx.TensorProto.INT64, [1, "seq"])
out_val = oh.make_tensor_value_info("output", onnx.TensorProto.FLOAT, [1, "seq"])
node = oh.make_node("Cast", ["attention_mask"], ["output"], to=onnx.TensorProto.FLOAT)
graph = oh.make_graph([node], "tiny_embed", [in_ids, in_mask], [out_val])
tiny_model = oh.make_model(graph, opset_imports=[oh.make_opsetid("", 19)])
tiny_model.ir_version = 10  # 兼容 onnxruntime 1.23（IR<=11）
onnx.save(tiny_model, tiny_onnx)
try:
    emb = rag._OnnxEmbeddings.__new__(rag._OnnxEmbeddings)
    emb._session = ort.InferenceSession(tiny_onnx)

    class FakeTok:
        def __call__(self, texts, **kwargs):
            return {
                "input_ids": np.array([[1, 2, 3]], dtype=np.int64),
                "attention_mask": np.array([[1, 1, 1]], dtype=np.int64),
            }

    emb._tokenizer = FakeTok()
    emb._input_names = ["input_ids", "attention_mask"]

    vec = emb._embed("测试文本")
    check("_embed 返回一维向量", isinstance(vec, list) and len(vec) == 3, f"vec={vec}")
    check("embed_query / embed_documents 可用",
          emb.embed_query("a") == vec and emb.embed_documents(["b", "c"]) == [vec, vec])

    # 缺 ONNX 模型时应给出明确报错
    try:
        rag.load_vectorstore("/nonexistent/vectorstore")
        check("load_vectorstore 缺 ONNX 模型时报错", False)
    except FileNotFoundError as e:
        check("load_vectorstore 缺 ONNX 模型时报错", "model.onnx" in str(e), str(e)[:60])
finally:
    if os.path.isfile(tiny_onnx):
        os.remove(tiny_onnx)

# ============================================================
# 5. build.main 文件链 Prompt 构造
# ============================================================
section("5. build.main 文件链 Prompt 构造")

build_fixture = {
    "query": "公司经营应遵守什么？",
    "timestamp": "2026-08-17 12:00:00",
    "total": 1,
    "results": [
        {"law_name": "中华人民共和国公司法", "article": "第五十八条",
         "content": "公司应当依法经营。", "source": "exact"}
    ],
}
try:
    # ---- 场景 A：正常 docs（模拟 rag_result.json） ----
    os.makedirs(PIPELINE_DIR, exist_ok=True)
    with open(RAG_JSON, "w", encoding="utf-8") as f:
        json.dump(build_fixture, f, ensure_ascii=False, indent=2)

    prompt = build.main()
    check("main 返回 prompt 含系统设定", "你是一个法律咨询专用模型。" in prompt)
    check("prompt 含条文标题", "《中华人民共和国公司法》第五十八条" in prompt, "第五十八条" in prompt)
    check("prompt 含条文内容", "公司应当依法经营。" in prompt)
    check("prompt 含用户问题", "公司经营应遵守什么？" in prompt)
    check("prompt 含【回答】段", "【回答】" in prompt)
    check("prompt.txt 已写入", os.path.isfile(PROMPT_TXT), PROMPT_TXT)
    with open(PROMPT_TXT, "r", encoding="utf-8") as f:
        check("prompt.txt 内容与返回值一致", f.read() == prompt)

    # ---- 场景 B：空 docs 兜底 ----
    with open(RAG_JSON, "w", encoding="utf-8") as f:
        json.dump({"query": "你好", "timestamp": "2026-08-17 12:00:00", "total": 0, "results": []},
                  f, ensure_ascii=False, indent=2)
    prompt_empty = build.main()
    check("空 docs 走兜底文案", "（未检索到可用法律条文）" in prompt_empty)
finally:
    cleanup_pipeline()

# ============================================================
# 6. asr.run 语音转文字链路（mock 模型 + 合成音频）+ asr_result.txt
# ============================================================
section("6. asr.run 语音转文字链路（mock 模型 + 合成音频）+ asr_result.txt")
import numpy as np


class FakeASR:
    """模拟 Paraformer 模型：返回 funasr-onnx 相同结构的结果。"""

    def __call__(self, wav_paths):
        return [{"preds": ("我要咨询劳动法问题", ["我", "要", "咨", "询"])}]


_orig_asr_model = asr._get_audio_model


def _fake_audio_model():
    # 与真实 _get_audio_model 一致：确保临时 wav 缓存目录存在
    os.makedirs(asr.AUDIO_CACHE_DIR, exist_ok=True)
    return FakeASR()


asr._get_audio_model = _fake_audio_model
try:
    sr = asr.TARGET_SR
    # 1 秒 440Hz 正弦波（非零幅值，满足归一化与时长>=0.8s 校验）
    data = (np.sin(np.linspace(0, 2 * np.pi * 440, sr)) * 0.5).astype(np.float32)
    text = asr.run((sr, data))
    check("run 返回识别文本", text == "我要咨询劳动法问题", f"got {text!r}")
    check("asr_result.txt 已生成", os.path.isfile(ASR_TXT), ASR_TXT)
    with open(ASR_TXT, "r", encoding="utf-8") as f:
        check("asr_result.txt 内容为识别文本", f.read() == text)

    # 非 16k 采样率：验证纯 numpy 重采样路径（原 librosa 已移除）
    data48 = (np.sin(np.linspace(0, 2 * np.pi * 440, 48000)) * 0.5).astype(np.float32)
    text48 = asr.run((48000, data48))
    check("run 支持非 16k 采样率（重采样路径）", text48 == "我要咨询劳动法问题", f"got {text48!r}")

    out = asr._resample(data48, 48000, 16000)
    check("_resample 输出长度正确", len(out) == 16000, f"len={len(out)}")
    check("_resample 输出为 float32", out.dtype == np.float32, f"dtype={out.dtype}")

    text_none = asr.run(None)
    check("audio=None 返回提示", text_none == "未检测到语音输入", f"got {text_none!r}")
finally:
    asr._get_audio_model = _orig_asr_model
    # 清理测试产生的临时缓存与流水线产物
    cache = asr.AUDIO_CACHE_DIR
    if os.path.isdir(cache):
        shutil.rmtree(cache, ignore_errors=True)
    cleanup_pipeline()

# ============================================================
# 7. tokenize.main 分词链路（mock tokenizer）+ model_inputs.pkl
# ============================================================
section("7. tokenize.main 分词链路（mock tokenizer）+ model_inputs.pkl")


class FakeTokenizer:
    """模拟 Qwen3 tokenizer：记录 chat 模板与分词调用参数。"""

    def __init__(self):
        self.calls = []

    def apply_chat_template(self, messages, tokenize=False, add_generation_prompt=True):
        self.calls.append(("template", messages, add_generation_prompt))
        return "<templated>"

    def __call__(self, texts, return_tensors="pt"):
        self.calls.append(("tokenize", return_tensors))
        return {"input_ids": [1, 2, 3], "return_tensors": return_tensors}


fake_tok = FakeTokenizer()
_orig_tok = tokenize._get_tokenizer
tokenize._get_tokenizer = lambda: fake_tok
try:
    # 模拟 build.main() 产出的 prompt.txt
    os.makedirs(PIPELINE_DIR, exist_ok=True)
    with open(PROMPT_TXT, "w", encoding="utf-8") as f:
        f.write("最终prompt")

    model_inputs = tokenize.main()
    check("main 返回模型输入", model_inputs["return_tensors"] == "pt", str(model_inputs))
    check("model_inputs.pkl 已生成", os.path.isfile(MODEL_INPUTS_PKL), MODEL_INPUTS_PKL)
    with open(MODEL_INPUTS_PKL, "rb") as f:
        loaded = pickle.load(f)
    check("pkl 可反序列化且内容一致", loaded == model_inputs, str(loaded))

    expected_tpl = ("template", [{"role": "user", "content": "最终prompt"}], True)
    check("套用 chat 模板并开启生成提示", fake_tok.calls[0] == expected_tpl, str(fake_tok.calls[0]))
    check("分词调用 return_tensors=pt", fake_tok.calls[1] == ("tokenize", "pt"), str(fake_tok.calls[1]))
finally:
    tokenize._get_tokenizer = _orig_tok
    cleanup_pipeline()

# ============================================================
# 8. 真实资源端到端测试（资源已下载时执行）
# ============================================================
section("8. 真实资源端到端测试（resources/ 已下载时执行）")

vec_dir = os.path.join(RESOURCES_DIR, "vectorstore", "law_faiss")
if os.path.isdir(vec_dir):
    t0 = time.time()
    try:
        os.environ["RAG_QUERY"] = "公司法第五十八条的内容是什么？"
        docs_real = rag.main()
        check("rag.main 真实向量库检索", isinstance(docs_real, list) and len(docs_real) > 0,
              f"len={len(docs_real)} 耗时{time.time() - t0:.1f}s")
    except Exception as e:
        check("rag.main 真实向量库检索", False, repr(e))
    finally:
        os.environ.pop("RAG_QUERY", None)
        cleanup_pipeline()
else:
    skip("rag.main 真实向量库检索", f"缺少 {vec_dir}")

tok_dir = os.path.join(RESOURCES_DIR, "tokenizer")
if os.path.isdir(tok_dir):
    try:
        os.makedirs(PIPELINE_DIR, exist_ok=True)
        with open(PROMPT_TXT, "w", encoding="utf-8") as f:
            f.write("测试")
        mi = tokenize.main()
        check("tokenize.main 真实分词", hasattr(mi, "input_ids"),
              f"{type(mi).__name__} 含 input_ids")
    except Exception as e:
        check("tokenize.main 真实分词", False, repr(e))
    finally:
        cleanup_pipeline()
else:
    skip("tokenize.main 真实分词", f"缺少 {tok_dir}")

am_dir = os.path.join(RESOURCES_DIR, "audio_model")
if os.path.isdir(am_dir):
    skip("asr.run 真实语音识别", "真实 ASR 需麦克风音频，本测试仅做 mock 链路验证")
else:
    skip("asr.run 真实语音识别", f"缺少 {am_dir}")

# ============================================================
# 9. 汇总
# ============================================================
section("测试汇总")
print(f"  PASS: {_PASS}")
print(f"  FAIL: {_FAIL}")
print(f"  SKIP: {_SKIP}")
print()
if _FAIL:
    print("  ❌ 存在失败用例，请检查输出。")
    sys.exit(1)
print("  ✅ 全部通过（SKIP 项为资源未下载，不计入失败）。")
