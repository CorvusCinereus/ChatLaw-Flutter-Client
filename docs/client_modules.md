# 客户端 Python 模块说明（ChatLaw Flutter 客户端）

本文档说明 `chatlaw-flutter-client/python/` 下 4 个独立模块（`asr.py` / `rag.py` / `build.py` / `tokenize.py`）的设计、用法、Android 打包需求与测试方法。

## 目录

1. [概述](#1-概述)
2. [环境与约定](#2-环境与约定)
3. [流水线文件链](#3-流水线文件链)
4. [模块详解](#4-模块详解)
5. [依赖清单（Android 兼容集）](#5-依赖清单android-兼容集)
6. [Android 打包指南](#6-android-打包指南)
7. [测试](#7-测试)

---

## 1. 概述

这 4 个模块把客户端流水线「语音转文字 → RAG 检索 → 构建 prompt → 分词」四个环节，从原本分散的函数整理为独立模块。

| 模块 | 环节 | 统一入口 | 输入来源 | 输出文件（pipeline/ 下） | Android 状态 |
|---|---|---|---|---|---|
| `python/asr.py` | ① 语音转文字 | `run(audio)` | 麦克风音频（APP 传入） | `asr_result.txt` | 桌面工具（Android 由系统语音识别替代） |
| `python/rag.py` | ② 知识库检索 | `main()` | 环境变量 `RAG_QUERY` | `rag_result.json` | ✅ 可用（需 `model.onnx`） |
| `python/build.py` | ③ 构建 prompt | `main()` | 读取 `rag_result.json` | `prompt.txt` | ✅ 可用 |
| `python/tokenize.py` | ④ 分词 | `main()` | 读取 `prompt.txt` | `model_inputs.pkl` | ✅ 可用 |

设计要点：

- 不依赖原 ChatLaw 仓库代码（`client_pt.py`、`common_utils.py` 等均未改动），可独立运行。
- 资源（Paraformer / 向量库 / tokenizer）采用**首次调用时懒加载并缓存**，模块 import 时不会触发任何下载或加载。
- 模块为**自包含实现**：资源路径与下载逻辑内嵌在各模块内，资源根目录优先读取环境变量 `APPDATA_DIR`，未设置时回退到 `<仓库根>/resources/`。
- 各模块构成**独立可执行的脚本链**：rag / build / tokenize 暴露统一入口 `main()`（可经 `__main__` 直接运行），输入/输出经 `{APPDATA_DIR}/pipeline/` 下的文件串联；asr 保持 `run()` 供 APP 进程内调用。
- 依赖清单为 **Android 兼容集**（见 [第 5 节](#5-依赖清单android-兼容集)）：编译型依赖均有 `pypi.flet.dev` 的 android wheel（含 Python 3.14，无需 `--python-version`）。

---

## 2. 环境与约定

### 2.1 Python 包导入方式（⚠️ 重要）

`python/` 是一个 Python 包（含 `__init__.py`），4 个模块必须以命名空间方式导入：

```python
from python import asr, rag, build, tokenize   # 或 import python.asr
```

**切勿**把 `python/` 目录直接加进 `sys.path` 后顶层导入（`import tokenize`）——顶层模块名 `tokenize` 会遮蔽标准库 `tokenize`，导致 transformers / torch / linecache 等内部 `import tokenize` 时解析到本模块，引发连锁循环导入（`inspect` / `AutoTokenizer` 报错）。

### 2.2 资源根目录 `APPDATA_DIR`

各模块通过 `os.getenv("APPDATA_DIR")` 读取资源根目录，该变量由宿主 APP 在启动 Python 进程前传入；未设置时回退到 `<仓库根>/resources/`（便于独立运行与测试）。

例：`APPDATA_DIR=D:/appdata` 时，向量库路径为 `D:/appdata/vectorstore/law_faiss`。

### 2.3 环境变量清单

| 变量 | 必填 | 设置方 | 说明 |
|---|---|---|---|
| `APPDATA_DIR` | ✅ | 宿主 APP | 资源根目录（见 [6.2](#62-资源打包)） |
| `RAG_QUERY` | 每次调用 rag 时 | 宿主 APP | rag 的查询文本（语音识别文本 / 用户输入） |

### 2.4 流水线输出目录

所有中间产物统一写入 `{APPDATA_DIR}/pipeline/`，由各模块的 `_get_pipeline_dir()` 计算（`os.path.join(_get_resources_path(), "pipeline")`），写文件前自动 `os.makedirs`，写失败仅打印 stderr 警告、不中断主流程。

---

## 3. 流水线文件链

```
{APPDATA_DIR}/pipeline/
├── asr_result.txt      # asr.run 输出：识别文本
├── rag_result.json     # rag.main 输出：归一化结果（含 query 字段）
├── prompt.txt          # build.main 输出：最终 prompt
└── model_inputs.pkl    # tokenize.main 输出：pickle 序列化的 model_inputs

asr.run(audio) ──文本──▶ asr_result.txt（同时返回文本给 APP）
rag.main()（读环境变量 RAG_QUERY）────▶ rag_result.json ──▶ 返回 docs
build.main()（读 rag_result.json）──▶ prompt.txt ──▶ 返回 prompt
tokenize.main()（读 prompt.txt）──▶ model_inputs.pkl ──▶ 返回 model_inputs
```

APP 侧典型编排：

- **Android**：语音经系统原生语音识别转文本 → 以环境变量 `RAG_QUERY=<文本>` 启动 `python -m python.rag` → 依次启动 `python -m python.build`、`python -m python.tokenize` → 读取 `model_inputs.pkl` 发送给服务端。
- **桌面**：可先用 `asr.run(audio)` 取文本，其余环节相同。

| 文件 | 产出模块 | 内容 | 消费方 |
|---|---|---|---|
| `asr_result.txt` | asr.run | 识别文本 | 桌面端 APP（Android 用系统识别） |
| `rag_result.json` | rag.main | `{query, timestamp, total, results[]}`，每条含 `law_name/article/content/source` | build.main |
| `prompt.txt` | build.main | 最终推理 prompt | tokenize.main |
| `model_inputs.pkl` | tokenize.main | pickle 序列化的模型输入（`return_tensors="pt"`） | 服务端 |

---

## 4. 模块详解

### 4.1 `asr.run`（桌面工具）

- **功能**：语音转文字环节的统一入口（保留 `run` 命名，供 APP 进程内调用）。一次调用即可完成「音频预处理 → 写入临时 wav → Paraformer 推理 → 解析识别结果」整个 ASR 流程，返回中文文本，并同时把文本写入 `{APPDATA_DIR}/pipeline/asr_result.txt`。**本模块为桌面/开发工具**：Android 上 funasr_onnx 及其依赖无 Android wheel，语音转文字由 Android 原生语音识别完成（文本直接进入 rag）。
- **参数**：
  - `audio`（必填）：`(sample_rate, numpy_array)` 元组，即 Gradio `gr.Audio(type="numpy")` 麦克风输入。
    - `sample_rate`：`int`，音频采样率（如 44100 / 48000）。若与目标采样率 `16000` 不同，内部会用纯 numpy 线性插值 `_resample()` 重采样到 16k（不依赖 librosa，保证在无 numba wheel 的平台可安装）。
    - `numpy_array`：`numpy.ndarray`，音频数据。若为立体声（`ndim > 1`），内部会先取各声道均值转单声道；随后转 `float32`、做幅值归一化（最大幅值归一化到 0.9，防止音量过小）。
    - 若传入 `None`，直接返回提示文本 `"未检测到语音输入"`。
  - 模块内部固定使用（无需外部传入）：`TARGET_SR = 16000`（目标采样率）、`AUDIO_CACHE_DIR = {APPDATA_DIR}/_asr_cache`（临时 wav 缓存目录）、懒加载的 `Paraformer` 模型实例。
- **返回值**：`str`。
  - 正常：识别出的中文文本（同时写入 `asr_result.txt`）。
  - 各类异常情况返回提示文本：`"未检测到语音输入"`、`"语音过短，请说完整一句话"`（时长 < 0.8 秒）、`"ASR 推理异常: <e>"`、`"未识别到有效内容"`。
  - 特殊：识别结果为空字符串时会**抛出** `ValueError("语音未识别到有效内容！")`。
- **位置**：`python/asr.py:211`
- **内部实现**：调用模块内搬入的原函数 `speech_to_text(audio, target_sr, audio_cache_dir, audio_model)`（原样搬自 `common_utils.py:156`，其中重采样已改为模块内纯 numpy 实现 `_resample()`，不依赖 librosa；wav 写入改用标准库 `wave`，不依赖 soundfile），资源由 `_get_audio_model()`（`asr.py:89`）懒加载提供（首次调用时 `_download_audio_model()` 从启智社区补齐资源，`funasr_onnx` 为延迟导入，Android 上未安装时模块仍可 import）；`_save_asr_result()`（`asr.py:197`）把文本写入 pipeline 子目录。

### 4.2 `rag.main`

- **功能**：知识库检索环节的统一入口。一次调用即可完成「精确索引检索（某法第几条）→ 未命中兜底 FAISS 语义检索 → 混合结果去重合并 → 归一化落盘」整个 RAG 流程，返回统一格式的检索结果列表。
- **环境变量（输入）**：
  - `RAG_QUERY`（必填）：`str`，用户咨询文本，由宿主 APP 在启动 `python -m python.rag` 前设置。缺失时打印 `[rag] 缺少环境变量 RAG_QUERY` 并以退出码 1 结束。内部会先做法条解析：
    - 用正则提取条号（匹配 `第[一二三四五六七八九十百千万零〇两\d]+条`）；
    - 在所有已知法条名中做"最长子串匹配"定位法律名（如 `"公司法第五十八条的内容是什么？"` → 法条名 `"公司法"`、条号 `"第五十八条"`）。
  - 检索条数保持默认：精确命中时 1 条精确 + 1 条 FAISS 补充，未命中时直接 FAISS 5 条。
- **输出文件**：`{APPDATA_DIR}/pipeline/rag_result.json`，每次运行覆盖。JSON 结构示例：
  ```json
  {
    "query": "公司经营应遵守什么？",
    "timestamp": "2026-08-17 12:00:00",
    "total": 2,
    "results": [
      { "law_name": "中华人民共和国公司法", "article": "第五十八条", "content": "…", "source": "exact" },
      { "law_name": "民法典", "article": "第一条", "content": "…", "source": "faiss" }
    ]
  }
  ```
- **返回值**：`list`，统一格式的检索结果（FAISS Document 或精确索引 dict），进程内调用时可直接使用。
- **位置**：`python/rag.py:455`（`__main__` 入口在 `:482`）
- **内部实现**：检索逻辑由模块内搬入的 `retrieve_laws(...)` 混合检索函数完成（原样搬自 `common_utils.py:426`），其内部串联 `retrieve_laws_exact`（精确索引）、`retrieve_laws_faiss`（FAISS）、`merge_docs_keep_order`（去重合并）；资源由 `_get_resources()`（`rag.py:96`）懒加载提供（首次调用时 `_download_vectorstore()` 从启智社区补齐资源）。向量嵌入由 `_OnnxEmbeddings`（`rag.py:186`，onnxruntime，无 torch 依赖，Android 可用）实现，模型约定为 `{资源根}/vectorstore/embedding_model/model.onnx`（桌面端导出后随资源打包）。归一化由 `_doc_to_record()`（`rag.py:392`）完成：多键回退兼容新旧版向量库，`source` 按元素类型推断（dict → `"exact"`、Document → `"faiss"`）；落盘由 `_save_docs_json()`（`rag.py:432`）完成，写失败仅打印 stderr 警告，不中断检索。

### 4.3 `build.main`

- **功能**：Prompt 构建环节的统一入口。从 `{APPDATA_DIR}/pipeline/rag_result.json` 读取 `query` 与 `results`，把用户问题与检索到的法律条文拼装成最终推理 prompt（含系统法律助手设定、【参考法条】上下文、【用户问题】两段结构 + 问题正文），写入 `{APPDATA_DIR}/pipeline/prompt.txt`。
- **输入（文件）**：`{APPDATA_DIR}/pipeline/rag_result.json`（由 `rag.main()` 生成），缺失时打印错误并以退出码 1 结束。
  - `question` = 文件中的 `query` 字段；
  - `docs` = 文件中的 `results` 列表（已归一化记录，含 `law_name` / `article` / `content` / `source`，直接兼容 `_format_doc_block` 的 dict 分支）。
- **输出（文件）**：`{APPDATA_DIR}/pipeline/prompt.txt`，内容为最终 prompt。
- **返回值**：`str`，组装好的最终推理 prompt（进程内调用时可直接使用）。
- **位置**：`python/build.py:99`（`__main__` 入口在 `:133`）
- **内部实现**：调用模块内搬入的 `build_prompt(question, docs)`（原样搬自 `common_utils.py:499`），其内部使用 `_format_doc_block`（原样搬自 `common_utils.py:465`）逐条格式化。本模块无资源加载，为纯字符串拼接。

### 4.4 `tokenize.main`

- **功能**：分词环节的统一入口。从 `{APPDATA_DIR}/pipeline/prompt.txt` 读取最终 prompt，完成「套用 Qwen3 对话模板（chat template）→ 分词 → pickle 序列化落盘」整个分词流程，产出可直接发送给服务端的模型输入。
- **输入（文件）**：`{APPDATA_DIR}/pipeline/prompt.txt`（由 `build.main()` 生成），缺失时打印错误并以退出码 1 结束。
- **输出（文件）**：`{APPDATA_DIR}/pipeline/model_inputs.pkl`，为 `pickle.dump` 序列化的 model_inputs（含 `input_ids`、`attention_mask` 等 PyTorch 张量，`return_tensors="pt"` 对应 Transformers 服务端）。消费侧用 `pickle.load` 读取。
- **返回值**：`model_inputs`，分词后的模型输入（进程内调用时可直接使用）。
- **位置**：`python/tokenize.py:100`（`__main__` 入口在 `:138`）
- **内部实现**：构建 `messages = [{"role": "user", "content": final_prompt}]` → `apply_chat_template(messages, tokenize=False, add_generation_prompt=True)` 生成带生成提示的模板文本 → `tokenizer([templated], return_tensors="pt")` 分词。逻辑原样搬自 `client_pt.py:240-244` / `client_ms.py:240-244`；tokenizer 由 `_get_tokenizer()`（`tokenize.py:83`）懒加载提供（首次调用时 `_download_tokenizer()` 从启智社区补齐资源）。Qwen3 走 fast tokenizer（`tokenizers` 库，Android 有 wheel），无需 torch / sentencepiece。

---

## 5. 依赖清单（Android 兼容集）

`python/requirements.txt` 为 **Android 兼容集**：编译型依赖全部钉到 `pypi.flet.dev` 镜像上存在 android wheel 的版本（含 Python 3.14 的 cp314），纯 Python 依赖可跨平台。

### 5.1 requirements.txt 内容

```text
numpy==2.4.6
faiss-cpu==1.14.3
onnxruntime==1.27.0
langchain-community
transformers
```

传递依赖（自动携带，镜像均有 android wheel）：`tokenizers` / `safetensors` / `huggingface-hub` / `langchain-core` / `langchain-classic` / `scipy` / `pyyaml` 等。

**已移除的包及原因**：

| 包 | 原因 |
|---|---|
| `funasr_onnx` | 其 `numpy<=1.26.4` 约束锁死 Python<=3.12；依赖的 `onnx` / `kaldi-native-fbank` / `sentencepiece` / `librosa(numba)` 均无 Android wheel。ASR 改由 Android 原生语音识别完成 |
| `soundfile` / `librosa` | asr 的 wav 写入改用标准库 `wave`，重采样为纯 numpy `_resample()` |
| `langchain-huggingface` / `sentence-transformers` | 依赖 torch（无 Android wheel）；向量嵌入改用 onnxruntime `_OnnxEmbeddings` |
| `openi` | 其依赖 `pwinput` 仅有源码包（无 wheel），Flet `--only-binary :all:` 无法安装；资源应随 APP 打包 |

### 5.2 标准库

| 库 | 模块 | 用途 |
|---|---|---|
| `os` | asr / rag / build / tokenize | 路径拼接、目录创建、删除临时 wav 文件 |
| `re` | rag | 法条名规范化、条号/法律名正则解析 |
| `json` | rag / build | 读写 `rag_result.json` 等 JSON 文件 |
| `time` | asr / rag | 确保 wav 落盘、JSON 时间戳 |
| `uuid` | asr | 生成临时 wav 文件名（`uuid4().hex`） |
| `wave` | asr | 用标准库写入 PCM_16 wav（替代 soundfile，Android 兼容） |
| `sys` | asr / rag / build / tokenize | stderr 警告、`sys.exit(1)` 错误退出 |
| `pickle` | tokenize | `model_inputs.pkl` 序列化/反序列化 |

### 5.3 第三方库

| 库 | 模块 | 用途 |
|---|---|---|
| `numpy` | asr / rag | 音频处理与线性插值重采样（`_resample`）；FAISS/onnxruntime 的数值基础 |
| `onnxruntime` | rag | `_OnnxEmbeddings`：向量嵌入推理（Android 有 wheel，替代 torch） |
| `langchain_community` | rag | `FAISS` 向量库加载（`FAISS.load_local`，`allow_dangerous_deserialization=True`） |
| `transformers` | rag / tokenize | Qwen3 tokenizer（fast）、`apply_chat_template`、分词；embedding 的 tokenizer |
| `tokenizers` | rag / tokenize | 快速分词（transformers 自动携带，Android 有 wheel） |

注：`funasr_onnx` / `soundfile` / `langchain-huggingface` / `sentence-transformers`（torch 链）不在 Android 依赖清单中；桌面端需要 ASR 或 torch 版嵌入时手动安装。

### 5.4 内嵌资源逻辑（自包含，无外部项目依赖）

| 函数 | 模块 | 用途 |
|---|---|---|
| `_get_resources_path()` | asr / rag / build / tokenize | 返回资源根目录：优先读取环境变量 `APPDATA_DIR`，未设置时回退到 `<仓库根>/resources` |
| `_get_pipeline_dir()` | asr / rag / build / tokenize | 返回流水线输出子目录 `{资源根}/pipeline` |
| `_files_complete()` | asr / rag / tokenize | 检查资源目录是否存在且文件齐全 |
| `_download_audio_model()` | asr | 缺失时从启智社区（openi）下载 Paraformer 到 `{APPDATA_DIR}/audio_model` |
| `_download_vectorstore()` | rag | 缺失时从启智社区（openi）下载预构建向量库到 `{APPDATA_DIR}/vectorstore` |
| `_download_tokenizer()` | tokenize | 缺失时从启智社区（openi）下载 tokenizer 到 `{APPDATA_DIR}/` |
| `_save_asr_result()` | asr | 把识别文本写入 `{APPDATA_DIR}/pipeline/asr_result.txt` |
| `_resample()` | asr | 纯 numpy 线性插值重采样（替代 librosa.resample，消除 numba/llvmlite 依赖） |
| `_doc_to_record()` | rag | 把单条检索结果（dict / Document）归一化为 `{law_name, article, content, source}` 统一记录 |
| `_save_docs_json()` | rag | 把检索结果归一化后写入 `{APPDATA_DIR}/pipeline/rag_result.json`（`main()` 自动调用） |
| `_OnnxEmbeddings` | rag | onnxruntime 向量嵌入类（模型 `embedding_model/model.onnx`，无 torch 依赖，Android 可用） |

注：`openi` 为延迟导入（仅在资源缺失触发下载时引入），且**不在 `requirements.txt` 中**——其依赖 `pwinput` 仅有源码包（无 wheel），在 Flet 的 `--only-binary :all:` 构建下任何 Python 版本都无法安装；移动端资源应随 APP 打包进 APPDATA_DIR，开发环境需要自动下载资源时手动 `pip install openi`。

### 5.5 Android wheel 钉版对照表

| 包 | 钉版 | 镜像 android wheel | 说明 |
|---|---|---|---|
| `numpy` | `2.4.6` | ✅ cp312/313/314 | 数值基础；勿用 >2.4.6（镜像未提供 android wheel） |
| `faiss-cpu` | `1.14.3` | ✅ cp312/313/314 | FAISS 向量库 |
| `onnxruntime` | `1.27.0` | ✅ cp312/313/314 | 向量嵌入推理 |
| `tokenizers` | 自动 | ✅ 0.23.1 cp312/313/314 | transformers 携带 |
| `safetensors` | 自动 | ✅ 0.8.0 cp312/313/314 | transformers 携带 |

---

## 6. Android 打包指南

本模块面向 **Flet 打包的 Android APK**（Flutter 端嵌入 Python 运行时）。打包方需满足以下需求。

### 6.1 构建（serious_python / Flet）

**前置条件**：Flutter SDK（≥3.47）+ Android SDK/NDK + `serious_python: ^4.6.0` 依赖（pubspec）。

#### serious_python 直接打包（实测验证通过）

```bash
# 在 chatlaw-flutter-client 仓库根目录执行
export SERIOUS_PYTHON_VERSION=3.14
export SERIOUS_PYTHON_APP="<暂存目录，如 build/app_staging>"   # Android 打包必需
dart run serious_python:main package <python_app_dir> -p Android \
  --arch arm64-v8a \
  --requirements=-r --requirements=python/requirements.txt
```

关键点（均实测确认）：

- **`--arch arm64-v8a` 必须指定**：serious_python 会按架构逐个跑 pip；onnxruntime 在 pypi.flet.dev 镜像只有 `arm64_v8a` / `x86_64` 的 android wheel，不指定时构建 `armeabi-v7a` 会在 pip 阶段报 `No matching distribution found for onnxruntime`。
- **requirements 文件要拆成两个值传**：`--requirements=-r --requirements=python/requirements.txt`（serious_python 把每个 `-r` 值原样追加为 pip 参数，只传文件路径会被当作包名报 `Invalid requirement`）。
- **`SERIOUS_PYTHON_APP` 必须设置**：Android 打包需要 app 暂存目录（stage 解包后的应用），缺失报 `SERIOUS_PYTHON_APP environment variable must be set`。
- 产物：依赖装到 `build/site-packages/arm64-v8a/`（含 Android 原生 `.so`），app 暂存到 `SERIOUS_PYTHON_APP`，供后续 `flutter build apk` 的 Gradle 步骤嵌入。

#### Flet 构建

```bash
flet build apk --arch arm64-v8a
# 旧版 Flet（<0.86）需同时指定 Python 3.12：
flet build apk --arch arm64-v8a --python-version 3.12
```

- **Python 版本**：默认 3.14 即可。requirements 已移除 `funasr_onnx`（其 `numpy<=1.26.4` 约束曾锁死 Python<=3.12），镜像有 numpy 2.4.6 / faiss-cpu 1.14.3 / onnxruntime 1.27.0 的 **cp314** android wheel。
- **ABI 限制**：**仅支持 arm64-v8a**（主流 64 位设备）。`armeabi-v7a` 因 onnxruntime 无对应 android wheel 无法构建（`onnxruntime` 是 rag 嵌入的运行时，暂无替代轮子）；如确需 v7a，需另行替换 embedding 运行时并调整依赖。
- **serious_python 经 Flutter 构建时**：会按 Gradle 的 `ndk.abiFilters` 逐个 ABI 跑 pip 安装 `python/requirements.txt`。必须在 `android/app/build.gradle.kts` 的 `defaultConfig` 中限制 `ndk { abiFilters += listOf("arm64-v8a") }`（本仓库已配置），否则构建 armeabi-v7a 时因 onnxruntime 无 wheel 解析失败。Python ≥ 3.13 起官方已放弃 32 位 Android（PEP 738），仅保留 arm64-v8a / x86_64。
- 构建时 Flet 会自动执行 `pip install --only-binary :all: --extra-index-url https://pypi.flet.dev -r python/requirements.txt`（按 `--arch` 指定的 Android ABI 解析）。
- **勿改动钉版**：`numpy==2.4.6` 等版本对应镜像 android wheel，升版后 Android 打包可能找不到轮子。

### 6.2 资源打包

模型 / 向量库 / tokenizer **必须随 APK 打包**，APP 首次启动时解压到 `APPDATA_DIR` 指向的可写目录（如 serious_python 的应用数据目录）。解压后目录结构必须为：

```
{APPDATA_DIR}/
├── vectorstore/
│   ├── law_article_index.json      # 精确索引
│   ├── law_name_index.json         # 法条名索引
│   ├── law_faiss/
│   │   ├── index.faiss             # FAISS 向量库
│   │   └── index.pkl
│   └── embedding_model/
│       ├── model.onnx              # ← ONNX 嵌入模型（含 pooling+normalize）
│       ├── model.onnx.data         # ← ONNX 外部权重（必须与 model.onnx 同目录，onnxruntime 自动加载）
│       └── …tokenizer 文件（tokenizer.json / tokenizer_config.json / vocab.txt 等）
├── tokenizer/
│   ├── merges.txt
│   ├── tokenizer.json
│   ├── tokenizer_config.json
│   └── vocab.json
└── audio_model/                    # 仅桌面端需要（Android 用系统语音识别）
```

- **资源来源**：桌面端从启智社区 openi 下载数据集 `enter/vectorstore`、`enter/QwenTokenizer`（`enter/Paraformer` 仅桌面）后，随包打入 APK。
- **`model.onnx` 导出（rag 在 Android 可用的前提）**：把 embedding 模型（bge-base-zh-v1.5，CLS pooling + L2 normalize）导出为 ONNX（**pooling 与 normalize 需内置于图中**）。导出脚本见 `D:\dev\export_embedding_onnx.py`（`conda activate ChatLaw_env` + `python export_embedding_onnx.py <embedding_model_dir>`，已验证 onnxruntime 与 torch 输出一致）。导出产物为 `model.onnx` + `model.onnx.data`（外部权重），**两个文件必须同目录打包**；`pytorch_model.bin` 可删除。缺失时 `rag.main()` 会明确报错。
- **已实测的资源包**：`D:\dev\chatlaw_android_resources\`（514MB，结构与本节一致），含真实向量库（FAISS 21950 条）+ tokenizer + model.onnx，端到端检索验证通过。
- 解压目标即 `APPDATA_DIR` 环境变量指向处（与 6.3 一致）。

### 6.3 环境变量注入

宿主 APP 在启动 Python 前注入：

| 变量 | 必填 | 值 |
|---|---|---|
| `APPDATA_DIR` | ✅ | 解压后的资源根目录（6.2 的目录结构） |
| `RAG_QUERY` | 每次调用 rag | 查询文本（语音识别结果 / 用户输入） |

serious_python 参考（Flutter 端实现）：

```dart
final p = ProcessRunner(
  script: ProcessScript.python(executable: pythonExecutable),
);
// 运行 rag（env 传入 APPDATA_DIR 与 RAG_QUERY）
await p.run(
  ProcessScript.pythonModule(moduleName: "python.rag", args: []),
  env: {"APPDATA_DIR": appDataDir, "RAG_QUERY": query},
  workingDirectory: pythonRoot,
);
```

### 6.4 流水线调用顺序

1. **取文本**：Android 用系统语音识别（`SpeechRecognizer`）或用户输入得到查询文本；
2. **rag**：`python -m python.rag`（env 带 `RAG_QUERY`）→ 产出 `pipeline/rag_result.json`；
3. **build**：`python -m python.build` → 产出 `pipeline/prompt.txt`；
4. **tokenize**：`python -m python.tokenize` → 产出 `pipeline/model_inputs.pkl`；
5. **推理**：读取 `model_inputs.pkl`（`pickle.load`），通过服务端链路发送给大模型推理。

注意：必须以 `-m python.xxx` 方式在仓库根目录运行（`python/` 是包，见 2.1）。

### 6.5 打包前核对清单

- [ ] `requirements.txt` 版本保持钉版（numpy==2.4.6 / faiss-cpu==1.14.3 / onnxruntime==1.27.0）
- [ ] 构建命令带 `--arch arm64-v8a`（勿构建 armeabi-v7a，onnxruntime 无对应 wheel）
- [ ] `vectorstore/embedding_model/model.onnx` 已导出并随包
- [ ] `vectorstore/`、`tokenizer/` 完整随包，解压后结构符合 6.2
- [ ] `APPDATA_DIR` / `RAG_QUERY` 注入逻辑已实现
- [ ] 构建用 Python 3.14（或 3.12），与镜像 android wheel 匹配

---

## 7. 测试

### 7.1 运行方式

```bash
conda activate ChatLaw_env
cd chatlaw-flutter-client
python python_test/test_client_modules.py
```

脚本不依赖 pytest，纯 `assert` + 显式 `[PASS] / [FAIL] / [SKIP]` 输出；存在失败用例时以非零退出码结束，并打印具体差异。

### 7.2 测试内容

| 分区 | 覆盖内容 | 说明 |
|---|---|---|
| 0. 环境信息 | Python 解释器 / 版本 / 模块目录 / 资源目录 / APPDATA_DIR / 流水线目录 | 显式打印运行环境 |
| 1. 模块导入 | 4 个模块可正常 import | import 不应触发任何资源下载/加载 |
| 2. 懒加载验证 | import 后各资源缓存为空 | 校验 `_vectorstore` / `_exact_index` / `_law_name_candidates` / `_audio_model` / `_tokenizer` 均为 `None` |
| 3. 法条解析纯逻辑 | `normalize_law_name` / `normalize_article_number` / `parse_law_article_query` | 精确解析与无关问题两种场景 |
| 4. `rag.main` 全链路 | 混合检索编排 + 自动保存 JSON | 设 `RAG_QUERY` 后走真实 `main()` 入口：精确命中 → 2 条、未命中 → faiss 5 条；校验 `pipeline/rag_result.json` 的生成、schema、来源标记与覆盖行为 |
| 4b. `_OnnxEmbeddings` | onnxruntime 向量嵌入 | 用微型 ONNX 模型验证 `_embed` / `embed_query` / `embed_documents`，及缺 `model.onnx` 时明确报错 |
| 5. `build.main` 文件链 | prompt 构造 | 写入 `rag_result.json` 后走真实 `main()`：校验返回 prompt 与 `prompt.txt` 内容，含空 docs 兜底 |
| 6. `asr.run` 全链路 | 语音转文字编排 + 落盘 + 重采样 | 替换 `_get_audio_model()` 为假模型 + 1 秒合成正弦波音频，校验识别文本与 `asr_result.txt` 内容，并验证非 16k 采样率下 `_resample()` 重采样路径；测试后自动清理缓存与 pipeline 产物 |
| 7. `tokenize.main` 文件链 | 分词编排 + pickle 落盘 | 写入 `prompt.txt` 后走真实 `main()`（mock tokenizer）：校验返回、`model_inputs.pkl` 可反序列化、chat 模板套用参数 |
| 8. 真实资源端到端 | `resources/` 已下载时执行 | 设 `RAG_QUERY` 后 `rag.main()` 真实检索、`tokenize.main()` 真实分词；资源缺失时显式 `[SKIP]`（资源在首次实际调用时自动下载，测试不代为下载） |

### 7.3 设计要点

- **mock 的是懒加载函数而非业务函数**：测试替换各模块的 `_get_*()` 懒加载函数为假资源，直接走真实 `main()`/`run()` 入口及其内部编排，验证的是入口完整链路与文件链产物。
- 真实资源（`APPDATA_DIR` 指向的资源根，未设置时为 `<仓库根>/resources/`）下载完成后重跑脚本，第 8 区会自动升级为真实端到端测试。

---

## 8. Flutter 侧接入（开发期：外部 Python 子进程）

### 8.1 新增的 Dart 文件

| 文件 | 职责 |
|---|---|
| `lib/internal/python_env.dart` | 桥接配置常量：`kPythonExe`（Python 解释器路径，默认本机 ChatLaw_env）、`kAppDataDir`（= APPDATA_DIR，默认 `D:\dev\chatlaw_android_resources`）、`kRepoRootOverride`（仓库根，空则取 `Directory.current`）。**部署/换机时替换这些常量** |
| `lib/services/chat_pipeline.dart` | `ChatPipeline`：`runRag(question)`（真实 RAG，解析 `rag_result.json` 返回 `RagDoc[]`）、`runBuild()`、`runTokenize()`（返回发往推理服务器的 pickle 负载字节）。Android 走内嵌 HTTP 服务（`/rag`、`/build`、`/tokenize`），桌面走 `Process.run(python, ['-m', 'python.xxx'])`。失败抛 `PipelineException`（含 stderr 摘要）。`ChatPipeline.debugOverride` 供 widget 测试注入假实现 |
| `lib/services/pickle_codec.dart` | 解析服务端 `/infer` 的分帧 pickle 响应：每帧 = 8 字节大端长度 + pickle 数据，内容为文本增量，`<END>` 为结束帧、`[ServerError] ...` 为错误帧。仅需解码（请求方向的 pickle 由设备端内嵌 Python 生成） |
| `lib/services/inference_client.dart` | `InferenceClient`：`checkHealth()`（POST 数据端口 `/health`）、`infer(payload)`（心跳端口 6005 持续 PING + 数据端口 6006 `POST /infer`，流式产出文本增量）。`InferenceClient.debugOverride` 供 widget 测试注入 |

### 8.2 ChatPage 驱动方式

`_sendMessage` → `_startProgress(question)`（替换原定时模拟体）：

1. `runRag` 真实完成 → 把每条结果的 `《law_name》article` 填入检索面板 `_caches`、`content` 填入 `_details` → 进度条步骤 1
2. `runBuild` 真实完成 → 步骤 2；`runTokenize` 真实完成 → 步骤 3（同时得到发往推理服务器的 pickle 负载）
3. 推理步骤 → 先 `InferenceClient.checkHealth()` 确认数据端口可达，再 `POST /infer` **流式接收**模型输出，随增量刷新 assistant 气泡 → 步骤 4
4. 收尾持久化：`_addHistory`（含 assistant 消息）、`_addCache`（真实检索条文）；失败时渲染错误气泡（推理中途失败则保留已收到的内容并标注中断）并持久化

### 8.3 测试

- `test/chat_pipeline_real_test.dart`：**真实端到端**——外部 python + 真实资源跑通 runRag/runBuild/runTokenize（本机需满足 python_env.dart 配置）
- `test/chat_page_flow_test.dart`：widget 测试——注入假 `ChatPipeline` 与假 `InferenceClient`，验证发送后检索法条落位抽屉、assistant 流式回答气泡、持久化回调、失败容错
- `test/pickle_codec_test.dart`：分帧 pickle 解析（含真实 Python 产出的字节样例、分包到达、错误帧）
- `test/inference_client_test.dart`：对本地 HttpServer 模拟服务端，验证健康检查、心跳 PING、`/infer` 请求体与内容长度、流式分帧解码

### 8.4 后续替换路径

- **接入 serious_python（Android 内嵌）**：已实现——`ChatPipeline` 在 `Platform.isAndroid` 分支改走内嵌 `main.py` HTTP 服务，UI 与调用点不变
- **接入推理服务器**：已实现——步骤 4 发送分词产出的 pickle 负载到 `SERVER_IP:6006/infer` 并流式渲染真实回答

---

## 9. Android 运行时架构与构建实测

### 9.1 运行时架构（serious_python 内嵌）

```
Flutter App (Android)
 ├─ lib/main.dart: SeriousPython.run(main.py)（后台线程；首次启动解包 app.zip 到
 │   <filesDir>/flet/app，含 main.py + python/ 包 + resources/ 514MB）
 ├─ ChatPipeline（Platform.isAndroid 分支）→ HTTP POST http://127.0.0.1:18765
 ├─ InferenceClient → 心跳 POST 6005/heartbeat；数据 POST 6006/health、6006/infer
 └─ 解析响应 docs → 检索抽屉；/infer 流式增量 → assistant 气泡
内嵌 Python（main.py，ThreadingHTTPServer，端口 18765 与 Dart 端 kPythonServicePort 一致）
 ├─ /rag      → os.environ['RAG_QUERY']=question → rag.main() → 回读
 │              pipeline/rag_result.json 返回 {ok, docs[]}
 ├─ /build    → build.main()
 ├─ /tokenize → tokenize.main() → 回传 {ok, payload_b64}（普通 dict + numpy 数组的 pickle）
 │              Dart 端 base64 解码后原样转发给推理服务器 6006/infer
 APPDATA_DIR 启动时设为 <app根>/resources（模块资源根约定）
```

### 9.2 构建实测流程（Windows / Linux 通用）

```bash
cd chatlaw-flutter-client
export SERIOUS_PYTHON_VERSION=3.14
export SERIOUS_PYTHON_SITE_PACKAGES="$(pwd)/build/site-packages"
export SERIOUS_PYTHON_APP="$(pwd)/build/python-app"

# 1) 组装 app 目录（main.py + python/ 包 + 514MB 资源；资源本地提供不入 git）
#    build/python_app/{main.py, python/, resources/}

# 2) 打包 python（arm64 单 ABI，与构建配对）
dart run serious_python:main package build/python_app -p Android \
  --arch arm64-v8a --requirements=-r --requirements=python/requirements.txt

# 3) 构建 APK（arm64 单 ABI）
flutter build apk --release --target-platform android-arm64
```

**github 直连不稳时的绕行方案**（实测：Gradle 下载 `flet-dev/python-build` dist 与
`flet-dev/dart-bridge` 会超时失败）：
1. 预下载到缓存（`~/.flet/cache/python-build/v3.14.7/` 与 `dart-bridge/v1.8.0/`，文件名与
   gradle 期望一致；直连失败可用镜像 `https://ghproxy.net/<github_url>`）；
2. 用 gradlew 直接构建并排除下载任务：
```bash
cd android
./gradlew :app:assembleRelease \
  -x :serious_python_android:downloadDistArchive_arm64-v8a \
  -x :serious_python_android:downloadDistArchive_armeabi-v7a \
  -x :serious_python_android:downloadDistArchive_x86_64 \
  -x :serious_python_android:downloadDartBridge_arm64-v8a \
  -x :serious_python_android:downloadDartBridge_armeabi-v7a \
  -x :serious_python_android:downloadDartBridge_x86_64
```

### 9.3 产物与注意

- APK ≈ **758MB**（app.zip 内含 514MB 真实资源；首次启动解包一次，耗时较长）
- 验证过的 APK 内容：assets `app.zip`（main.py + python/ + resources/）、
  `sitepackages.zip`（全部 Python 依赖）、`stdlib.zip`；`lib/arm64-v8a/` 含
  `libpython3.14.so`、`libdart_bridge.so`、`libfaiss-_swigfaiss.so`、
  `libonnxruntime-...pybind11_state.so`
- 真机最终验证：安装 APK → 发送问题 → 检索面板出现真实法条（首次启动等待 python 服务就绪）
