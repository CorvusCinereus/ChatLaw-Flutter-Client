# 新模块 run 函数说明

说明：以下整理 `python/` 下 4 个独立模块（`asr.py` / `rag.py` / `build.py` / `tokenize.py`）及其对外统一入口 `run()` 函数。

这些模块把客户端流水线「语音转文字 → RAG 检索 → 构建 prompt → 分词」四个环节，从原本分散的函数整理为独立模块。每个模块满足：

- 所需函数**原样搬入**模块内，不依赖原 client / server 实现文件（`client_pt.py`、`common_utils.py` 等均未改动）。
- 资源（Paraformer / 向量库 / tokenizer）采用**首次调用 `run()` 时懒加载并缓存**，模块 import 时不会触发任何下载或加载。
- 模块为**自包含实现**：资源路径与下载逻辑（openi 延迟导入）内嵌在各模块内，资源根目录优先读取环境变量 `APPDATA_DIR`（由宿主 APP 传入），未设置时回退到 `<仓库根>/resources/`，不依赖原 ChatLaw 仓库的 `launcher` / `chatlaw.dataloader`。
- 对外只暴露一个统一入口 `run()`，一次调用即可完成该环节的全部操作。

> **⚠️ 导入方式（重要）**：`python/` 是一个 Python 包（含 `__init__.py`），4 个模块必须以命名空间方式导入：
> `from python import asr, rag, build, tokenize`（或 `import python.asr`）。
> **切勿**把 `python/` 目录直接加进 `sys.path` 后顶层导入（`import tokenize`）——
> 顶层模块名 `tokenize` 会遮蔽标准库 `tokenize`，导致 transformers / torch / linecache 等内部
> `import tokenize` 时解析到本模块，引发连锁循环导入（`inspect` / `AutoTokenizer` 报错）。

> **📦 资源根目录（环境变量）**：各模块通过 `os.getenv("APPDATA_DIR")` 读取资源根目录，
> 该变量由宿主 APP 在启动 Python 进程前传入；未设置时回退到 `<仓库根>/resources/`。
> 例：`APPDATA_DIR=D:/appdata` 时，向量库路径为 `D:/appdata/vectorstore/law_faiss`。

## 模块概览

| 模块 | 对应环节 | 统一入口 | 懒加载资源 |
|---|---|---|---|
| `python/asr.py` | ① 语音转文字 | `run(audio)` | Paraformer 语音模型 |
| `python/rag.py` | ② 知识库检索 | `run(query, exact_faiss_k=1, faiss_only_k=5)` | FAISS 向量库 + 精确索引 + 法条名候选 |
| `python/build.py` | ③ 构建 prompt | `run(question, docs)` | 无（纯字符串拼接） |
| `python/tokenize.py` | ④ 分词 | `run(final_prompt, return_tensors="pt")` | Qwen3 tokenizer |

---

## 一、`asr.run`

- **功能**：语音转文字环节的统一入口。一次调用即可完成「音频预处理 → 写入临时 wav → Paraformer 推理 → 解析识别结果」整个 ASR 流程，返回中文文本。
- **参数**：
  - `audio`（必填）：`(sample_rate, numpy_array)` 元组，即 Gradio `gr.Audio(type="numpy")` 麦克风输入。
    - `sample_rate`：`int`，音频采样率（如 44100 / 48000）。若与目标采样率 `16000` 不同，内部会用 `librosa.resample` 重采样到 16k。
    - `numpy_array`：`numpy.ndarray`，音频数据。若为立体声（`ndim > 1`），内部会先取各声道均值转单声道；随后转 `float32`、做幅值归一化（最大幅值归一化到 0.9，防止音量过小）。
    - 若传入 `None`，直接返回提示文本 `"未检测到语音输入"`。
  - 模块内部固定使用（无需外部传入）：`TARGET_SR = 16000`（目标采样率）、`AUDIO_CACHE_DIR = {APPDATA_DIR}/_asr_cache`（临时 wav 缓存目录）、懒加载的 `Paraformer` 模型实例。
- **返回值**：`str`。
  - 正常：识别出的中文文本。
  - 各类异常情况返回提示文本：`"未检测到语音输入"`、`"语音过短，请说完整一句话"`（时长 < 0.8 秒）、`"ASR 推理异常: <e>"`、`"未识别到有效内容"`。
  - 特殊：识别结果为空字符串时会**抛出** `ValueError("语音未识别到有效内容！")`。
- **位置**：`python/asr.py:162`
- **内部实现**：调用模块内搬入的原函数 `speech_to_text(audio, target_sr, audio_cache_dir, audio_model)`（原样搬自 `common_utils.py:156`），资源由 `_get_audio_model()`（`asr.py:74`）懒加载提供（首次调用时 `_download_audio_model()` 从启智社区补齐资源）。

---

## 二、`rag.run`

- **功能**：知识库检索环节的统一入口。一次调用即可完成「精确索引检索（某法第几条）→ 未命中兜底 FAISS 语义检索 → 混合结果去重合并」整个 RAG 流程，返回统一格式的检索结果列表。
- **参数**：
  - `query`（必填）：`str`，用户咨询文本。内部会先做法条解析：
    - 用正则提取条号（匹配 `第[一二三四五六七八九十百千万零〇两\d]+条`）；
    - 在所有已知法条名中做"最长子串匹配"定位法律名（如 `"公司法第五十八条的内容是什么？"` → 法条名 `"公司法"`、条号 `"第五十八条"`）。
  - `exact_faiss_k`（可选）：`int`，默认 `1`。当精确检索命中时，额外补充的 FAISS 语义检索条数（最终返回 `1` 条精确命中 + `k` 条 FAISS 参考）。
  - `faiss_only_k`（可选）：`int`，默认 `5`。当精确检索未命中时，直接走 FAISS 语义检索返回的条数。
  - 模块内部固定使用（无需外部传入）：懒加载的 `vectorstore`（FAISS 向量库，位于 `{APPDATA_DIR}/vectorstore/law_faiss`）、`exact_index`（精确索引 `{APPDATA_DIR}/vectorstore/law_article_index.json`）、`law_name_candidates`（从精确索引提取并按长度倒序排列的法条名候选列表）。
- **返回值**：`list`，统一格式的检索结果列表，元素兼容两种类型：
  - 精确索引命中的 `dict`（键含 `law_name_raw` / `law_name` / `law_name_norm` / `article` / `content`）；
  - FAISS 返回的 LangChain `Document`（`metadata` + `page_content`）。
  - 该列表可直接传给 `build.run(question, docs)` 构建 prompt。
- **位置**：`python/rag.py:339`
- **内部实现**：调用模块内搬入的 `retrieve_laws(...)` 混合检索函数（原样搬自 `common_utils.py:426`），其内部串联 `retrieve_laws_exact`（精确索引）、`retrieve_laws_faiss`（FAISS）、`merge_docs_keep_order`（去重合并）；资源由 `_get_resources()`（`rag.py:81`）懒加载提供（首次调用时 `_download_vectorstore()` 从启智社区补齐资源）。模块内另搬入了 11 个检索辅助函数：`normalize_law_name`、`normalize_article_number`、`match_law_name_from_query`、`parse_law_article_query`、`load_vectorstore`、`load_exact_index`、`build_law_name_candidates`、`retrieve_laws_faiss`、`retrieve_laws_exact`、`_doc_unique_key`、`merge_docs_keep_order`。

---

## 三、`build.run`

- **功能**：Prompt 构建环节的统一入口。一次调用即可把用户问题与检索到的法律条文拼装成最终推理 prompt（含系统法律咨询设定、【法律条文】上下文、【问题】、【回答】四段结构）。
- **参数**：
  - `question`（必填）：`str`，用户咨询文本，会填入 prompt 的【问题】段。
  - `docs`（必填）：`list`，知识库检索结果列表（即 `rag.run()` 的返回值），元素为 FAISS `Document` 或精确索引 `dict`。内部会逐条调用 `_format_doc_block` 格式化为 `序号. 《法律名》条号：内容` 的形式，多条之间用空行分隔后填入【法律条文】段；若 `docs` 为空，则【法律条文】段显示 `（未检索到可用法律条文）`。
    - 对 FAISS `Document` 取值优先级：`metadata.law_name_raw` → `law_name` → `law_name_norm`，正文取 `metadata.content` 兜底 `page_content`；
    - 对精确索引 `dict` 取值优先级：`law_name_raw` → `law_name` → `law_name_norm`，正文取 `content`。
- **返回值**：`str`，组装好的最终推理 prompt，可直接传给 `tokenize.run(final_prompt)` 分词。
- **位置**：`python/build.py:72`
- **内部实现**：调用模块内搬入的 `build_prompt(question, docs)`（原样搬自 `common_utils.py:499`），其内部使用 `_format_doc_block`（原样搬自 `common_utils.py:465`）逐条格式化。本模块无资源加载，为纯字符串拼接。

---

## 四、`tokenize.run`

- **功能**：分词环节的统一入口。一次调用即可完成「套用 Qwen3 对话模板（chat template）→ 分词 → 返回模型输入张量」整个分词流程，产出可直接发送给服务端的模型输入。
- **参数**：
  - `final_prompt`（必填）：`str`，组装好的最终推理 prompt（即 `build.run()` 的返回值）。
  - `return_tensors`（可选）：`str`，返回张量类型，默认 `"pt"`。
    - `"pt"`：返回 PyTorch 张量（对应 pt 客户端 `client_pt.py`，配合 Transformers 服务端使用）；
    - `"np"`：返回 NumPy 数组（对应 ms 客户端 `client_ms.py`，配合 MindNLP 服务端使用）。
  - 模块内部固定使用（无需外部传入）：懒加载的 `tokenizer`（Qwen3 tokenizer，位于 `{APPDATA_DIR}/tokenizer`，`AutoTokenizer.from_pretrained(..., local_files_only=True)`）。
- **返回值**：`model_inputs`，分词后的模型输入批对象，含 `input_ids`、`attention_mask` 等张量/数组字段。pt 版为 `BatchEncoding`（PyTorch 张量），ms 版为 NumPy 数组，均可直接通过数据链路发送给服务端推理。
- **位置**：`python/tokenize.py:87`
- **内部实现**：构建 `messages = [{"role": "user", "content": final_prompt}]` → `apply_chat_template(messages, tokenize=False, add_generation_prompt=True)` 生成带生成提示的模板文本 → `tokenizer([templated], return_tensors=return_tensors)` 分词。逻辑原样搬自 `client_pt.py:240-244` / `client_ms.py:240-244`；tokenizer 由 `_get_tokenizer()`（`tokenize.py:70`）懒加载提供（首次调用时 `_download_tokenizer()` 从启智社区补齐资源）。

---

## 五、用到的所有库

### 标准库

| 库 | 模块 | 用途 |
|---|---|---|
| `os` | asr / rag / tokenize | 路径拼接、目录创建、删除临时 wav 文件 |
| `re` | rag | 法条名规范化、条号/法律名正则解析 |
| `json` | rag | 读取精确索引 `law_article_index.json` |
| `time` | asr | 确保 wav 文件完全落盘（Windows 必需，`sleep(0.05)`） |
| `uuid` | asr | 生成临时 wav 文件名（`uuid4().hex`） |

### 第三方库

| 库 | 模块 | 用途 |
|---|---|---|
| `numpy` | asr | 音频数组处理：转单声道、转 `float32`、幅值归一化 |
| `soundfile` | asr | 把音频数据写入 PCM_16 wav 临时文件 |
| `librosa` | asr | 音频重采样到 16k（`librosa.resample`） |
| `funasr_onnx` | asr | 语音识别模型 `Paraformer`（ONNX 量化版，中文 ASR） |
| `langchain_huggingface` | rag | `HuggingFaceEmbeddings`（sentence-transformers 向量化，`normalize_embeddings=True`） |
| `langchain_community` | rag | `FAISS` 向量库加载（`FAISS.load_local`，`allow_dangerous_deserialization=True`） |
| `transformers` | tokenize | `AutoTokenizer` 加载 Qwen3 tokenizer、`apply_chat_template`、分词 |

### 内嵌资源逻辑（自包含，无外部项目依赖）

| 函数 | 模块 | 用途 |
|---|---|---|
| `_get_resources_path()` | asr / rag / tokenize | 返回资源根目录：优先读取环境变量 `APPDATA_DIR`，未设置时回退到 `<仓库根>/resources` |
| `_files_complete()` | asr / rag / tokenize | 检查资源目录是否存在且文件齐全 |
| `_download_audio_model()` | asr | 缺失时从启智社区（openi）下载 Paraformer 到 `{APPDATA_DIR}/audio_model` |
| `_download_vectorstore()` | rag | 缺失时从启智社区（openi）下载预构建向量库到 `{APPDATA_DIR}/vectorstore` |
| `_download_tokenizer()` | tokenize | 缺失时从启智社区（openi）下载 tokenizer 到 `{APPDATA_DIR}/` |

注：`openi` 为延迟导入（仅在首次下载时引入），资源路径不再依赖原 ChatLaw 仓库的 `launcher.get_resources_path()` 与 `chatlaw.dataloader.download_resources()`。

---

## 六、测试脚本

4 个模块的自动化测试脚本位于 `python_test/test_client_modules.py`（另有 `test_rag_import.py` 为 RAG 库冒烟测试），用于验证各模块可正常使用。

### 运行方式

```bash
conda activate ChatLaw_env
cd chatlaw-flutter-client
python python_test/test_client_modules.py
```

脚本不依赖 pytest，纯 `assert` + 显式 `[PASS] / [FAIL] / [SKIP]` 输出；存在失败用例时以非零退出码结束，并打印具体差异。

### 测试内容

| 分区 | 覆盖内容 | 说明 |
|---|---|---|
| 0. 环境信息 | Python 解释器 / 版本 / 模块目录 / 资源目录 / APPDATA_DIR | 显式打印运行环境 |
| 1. 模块导入 | 4 个模块可正常 import | import 不应触发任何资源下载/加载 |
| 2. 懒加载验证 | import 后各资源缓存为空 | 校验 `_vectorstore` / `_exact_index` / `_law_name_candidates` / `_audio_model` / `_tokenizer` 均为 `None` |
| 3. 法条解析纯逻辑 | `normalize_law_name` / `normalize_article_number` / `parse_law_article_query` | 精确解析与无关问题两种场景 |
| 4. `rag.run` 全链路 | 混合检索编排 | 替换 `_get_resources()` 为假向量库/假索引后走真实 `run()` 入口：精确命中 → 2 条、未命中 → faiss 5 条、结果可直接喂给 `build.run` |
| 5. `build.run` 实际输出 | prompt 结构 | 校验系统设定 / 条文标题 / 条文内容 / 用户问题 / 【回答】段，及空 docs 兜底文案 |
| 6. `asr.run` 全链路 | 语音转文字编排 | 替换 `_get_audio_model()` 为假模型 + 1 秒合成正弦波音频，完整走「写 wav → 模型调用 → 结果解析」；`audio=None` 返回提示；测试后自动清理 `_asr_cache` 临时目录 |
| 7. `tokenize.run` 全链路 | 分词编排 | 替换 `_get_tokenizer()` 为假 tokenizer，校验 chat 模板套用（含生成提示）与 `return_tensors="pt"/"np"` 分支 |
| 8. 真实资源端到端 | `APPDATA_DIR` 指向的资源根（或回退的 `<仓库根>/resources`）已下载时执行 | 直接调用 `rag.run` / `tokenize.run` 真实检索/分词；资源缺失时显式 `[SKIP]`（资源在首次实际调用时自动下载，测试不代为下载） |

### 设计要点

- **mock 的是懒加载函数而非业务函数**：测试替换各模块的 `_get_*()` 懒加载函数为假资源，直接走真实 `run()` 入口及其内部编排，验证的是入口完整链路。
- 真实资源（`APPDATA_DIR` 指向的资源根，未设置时为 `<仓库根>/resources/`）下载完成后重跑脚本，第 8 区会自动升级为真实端到端测试。
