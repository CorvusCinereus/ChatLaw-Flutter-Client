# 客户端函数说明

说明：以下只整理客户端链路，不包含服务端函数。  
同名函数在 `pt` / `ms` 两个客户端实现中职责一致时，只写一条，并在“位置”里同时标出两个文件。

## 一、启动与配置

### 1. `get_project_root`
- 作用：返回项目根目录下的 `chatlaw` 路径，用作后续资源和脚本定位基准。
- 参数：无。
- 返回值：`str`，项目根目录路径。
- 位置：`launcher.py:9`

### 2. `get_resources_path`
- 作用：返回 `chatlaw/resources` 的绝对路径。
- 参数：无。
- 返回值：`str`，资源目录路径。
- 位置：`launcher.py:13`

### 3. `resolve_script_path`
- 作用：根据角色 `client/server` 和模式 `ms/pt` 拼出对应启动脚本路径，并检查文件是否存在。
- 参数：
  - `role`：启动角色，通常为 `client`。
  - `mode`：运行模式，`ms` 或 `pt`。
- 返回值：`str`，脚本绝对路径。
- 位置：`launcher.py:21`

### 4. `run_python_script`
- 作用：以子进程方式启动对应 Python 模块，并把额外命令行参数传递给目标脚本。
- 参数：
  - `script_path`：目标脚本路径。
  - `extra_args`：附加参数列表。
- 返回值：无显式返回，实际为 `None`。
- 位置：`launcher.py:67`

### 5. `main`
- 作用：解析 `chatlaw client ...` 命令并分发到对应客户端脚本。
- 参数：无。
- 返回值：无显式返回，实际为 `None`。
- 位置：`launcher.py:98`

### 6. `Config.__init__`
- 作用：把字典配置递归转换成可属性访问对象。
- 参数：
  - `cfg_dict`：配置字典。
- 返回值：构造函数，无显式返回。
- 位置：`chatlaw/configuration.py:12`

### 7. `Config.__str__`
- 作用：把配置对象格式化成可读字符串。
- 参数：无。
- 返回值：`str`，格式化后的配置内容。
- 位置：`chatlaw/configuration.py:20`

### 8. `parse_yaml`
- 作用：读取 YAML 配置文件并转成字典。
- 参数：
  - `yaml_path`：YAML 文件路径。
- 返回值：`dict`，配置内容。
- 位置：`chatlaw/configuration.py:23`

### 9. `parse_cli_args`
- 作用：根据 YAML 配置自动生成命令行参数并解析覆盖值。
- 参数：
  - `cfg`：默认配置字典。
- 返回值：`dict`，解析后的配置。
- 位置：`chatlaw/configuration.py:29`

### 10. `get_config`
- 作用：合并 YAML 配置和命令行参数，生成最终配置对象。
- 参数：无。
- 返回值：`Config` 实例。
- 位置：`chatlaw/configuration.py:39`

## 二、资源准备

### 11. `download_resources`
- 作用：按资源类型检查并下载 tokenizer、LLM、语音模型或向量库。
- 参数：
  - `resource_type`：资源类型，`tokenizer`、`llm`、`audio_model`、`vectorstore` 之一。
- 返回值：无显式返回，实际为 `None`。
- 位置：`chatlaw/dataloader/downloads.py:44`

### 12. `check_files_complete`
- 作用：检查某类资源目录是否存在且文件是否齐全。
- 参数：
  - `resource_type`：资源目录名。
  - `required_files`：需要存在的文件列表。
- 返回值：`bool`，是否完整。
- 位置：`chatlaw/dataloader/downloads.py:83`

## 三、客户端主流程

### 13. `alive_flag`
- 作用：向心跳线程提供当前客户端存活状态。
- 参数：无。
- 返回值：`bool`，当前 `alive` 标志。
- 位置：`chatlaw/client/client_pt.py:35`，`chatlaw/client/client_ms.py:35`

### 14. `_extract_doc_fields`
- 作用：统一抽取检索结果中的法条名称、条号和正文，兼容 FAISS `Document` 与精确索引 `dict`。
- 参数：
  - `item`：单条检索结果。
- 返回值：`tuple`，`(law_name, article, content)`。
- 位置：`chatlaw/client/client_pt.py:65`，`chatlaw/client/client_ms.py:65`

### 15. `format_retrieved_docs_html`
- 作用：把检索到的法条结果渲染成 HTML，显示在“查看知识库检索结果”面板中。
- 参数：
  - `docs`：检索结果列表。
- 返回值：`str`，HTML 字符串。
- 位置：`chatlaw/client/client_pt.py:100`，`chatlaw/client/client_ms.py:100`

### 16. `prepare_request_fn`
- 作用：完成第一阶段处理：校验输入、语音转文字、法规检索、构造最终 prompt，并解锁后续推理按钮。
- 参数：
  - `input_audio`：麦克风输入音频。
  - `input_text`：文本输入。
- 返回值：`tuple`，依次为状态文本、输出重置、检索面板 HTML、面板可见性、按钮状态、最终 prompt、检索面板显示状态。
- 位置：`chatlaw/client/client_pt.py:124`，`chatlaw/client/client_ms.py:123`

### 17. `stream_inference_fn`
- 作用：完成第二阶段处理：与服务端建立连接、发送模型输入、接收流式输出并持续刷新界面。
- 参数：
  - `final_prompt`：组装好的模型 prompt。
- 返回值：生成器，持续 `yield` 状态文本和当前输出内容。
- 位置：`chatlaw/client/client_pt.py:202`，`chatlaw/client/client_ms.py:201`

### 18. `toggle_retrieval_panel`
- 作用：切换“查看知识库检索结果”面板的显示/隐藏状态。
- 参数：
  - `visible_now`：当前是否可见。
- 返回值：`tuple`，`gr.update(...)` 和新的布尔状态。
- 位置：`chatlaw/client/client_pt.py:311`，`chatlaw/client/client_ms.py:306`

## 四、客户端公共工具

### 19. `recv_exact`
- 作用：从 socket 中精确读取指定字节数，直到满足长度或抛出异常。
- 参数：
  - `conn`：socket 连接。
  - `n`：期望读取的字节数。
  - `timeout`：可选超时时间。
- 返回值：`bytes`，精确读取到的数据。
- 位置：`chatlaw/client/utils/common_utils.py:16`

### 20. `render_mathml_from_latex`
- 作用：把 Markdown 文本中的 LaTeX 数学公式转换为 MathML。
- 参数：
  - `md_text`：包含公式的 Markdown 文本。
- 返回值：`str`，可渲染的 HTML/MathML 字符串。
- 位置：`chatlaw/client/utils/common_utils.py:49`

### 21. `connection_acknowledgement`
- 作用：与服务端做一次短连接握手，确认数据端口可用。
- 参数：
  - `server_ip`：服务端 IP。
  - `data_port`：数据端口。
  - `handshake_req`：握手请求字节。
  - `handshake_resp`：期望握手响应字节。
  - `recv_exact_fn`：精确读取函数。
  - `start_time`：开始时间戳。
- 返回值：`tuple`，状态文本和布尔成功标志。
- 位置：`chatlaw/client/utils/common_utils.py:94`

### 22. `speech_to_text`
- 作用：把音频输入转成中文文本。
- 参数：
  - `audio`：`(sample_rate, numpy_array)`。
  - `target_sr`：目标采样率。
  - `audio_cache_dir`：临时 wav 缓存目录。
  - `audio_model`：ASR 模型实例。
- 返回值：`str`，识别出的文本或错误提示。
- 位置：`chatlaw/client/utils/common_utils.py:156`

### 23. `normalize_law_name`
- 作用：规范化法条名称，便于精确匹配。
- 参数：
  - `law_name`：原始法条名。
- 返回值：`str`，规范化后的名称。
- 位置：`chatlaw/client/utils/common_utils.py:223`

### 24. `normalize_article_number`
- 作用：规范化条号格式，去除空白字符。
- 参数：
  - `article_number`：原始条号。
- 返回值：`str`，规范化后的条号。
- 位置：`chatlaw/client/utils/common_utils.py:241`

### 25. `match_law_name_from_query`
- 作用：从用户问题中匹配最可能的法条名称。
- 参数：
  - `query`：用户问题。
  - `law_name_candidates`：候选法条名列表。
- 返回值：`str | None`，命中的法条名或空值。
- 位置：`chatlaw/client/utils/common_utils.py:250`

### 26. `parse_law_article_query`
- 作用：从查询文本里解析法条名和条号。
- 参数：
  - `query`：用户问题。
  - `law_name_candidates`：候选法条名列表。
- 返回值：`tuple`，`(law_name, article)`。
- 位置：`chatlaw/client/utils/common_utils.py:267`

### 27. `load_vectorstore`
- 作用：加载 FAISS 向量库。
- 参数：
  - `path`：向量库路径。
- 返回值：`FAISS` 向量库对象。
- 位置：`chatlaw/client/utils/common_utils.py:297`

### 28. `load_exact_index`
- 作用：加载精确索引 JSON。
- 参数：
  - `index_path`：可选索引路径，默认使用资源目录。
- 返回值：`dict`，精确索引内容。
- 位置：`chatlaw/client/utils/common_utils.py:315`

### 29. `build_law_name_candidates`
- 作用：从精确索引里提取所有标准化法条名，并按长度排序。
- 参数：
  - `exact_index`：精确索引字典。
- 返回值：`list[str]`，候选法条名列表。
- 位置：`chatlaw/client/utils/common_utils.py:337`

### 30. `retrieve_laws_faiss`
- 作用：执行 FAISS 语义检索。
- 参数：
  - `vectorstore`：向量库对象。
  - `query`：查询文本。
  - `k`：返回条数。
- 返回值：`list`，相似文档列表。
- 位置：`chatlaw/client/utils/common_utils.py:352`

### 31. `retrieve_laws_exact`
- 作用：执行法条名 + 条号的精确检索。
- 参数：
  - `exact_index`：精确索引。
  - `query`：查询文本。
  - `law_name_candidates`：候选法条名列表。
- 返回值：`list[dict]`，命中的精确索引结果；未命中则为空列表。
- 位置：`chatlaw/client/utils/common_utils.py:359`

### 32. `_doc_unique_key`
- 作用：为检索结果生成唯一键，用于去重。
- 参数：
  - `item`：单条检索结果。
- 返回值：`str`，唯一键。
- 位置：`chatlaw/client/utils/common_utils.py:382`

### 33. `merge_docs_keep_order`
- 作用：按原顺序合并多组检索结果并去重。
- 参数：
  - `*doc_lists`：多个文档列表。
- 返回值：`list`，合并后的文档列表。
- 位置：`chatlaw/client/utils/common_utils.py:409`

### 34. `retrieve_laws`
- 作用：统一检索入口，先精确检索，命中后再补 FAISS；未命中则直接走 FAISS。
- 参数：
  - `vectorstore`：向量库对象。
  - `query`：查询文本。
  - `exact_index`：精确索引。
  - `law_name_candidates`：候选法条名。
  - `exact_faiss_k`：精确命中时补充的 FAISS 条数。
  - `faiss_only_k`：未命中时直接 FAISS 的条数。
- 返回值：`list`，统一后的检索结果。
- 位置：`chatlaw/client/utils/common_utils.py:426`

### 35. `_format_doc_block`
- 作用：把单条文档格式化成 prompt 中的上下文块。
- 参数：
  - `item`：单条检索结果。
  - `idx`：序号。
- 返回值：`str`，格式化后的条文块。
- 位置：`chatlaw/client/utils/common_utils.py:465`

### 36. `build_prompt`
- 作用：把用户问题和检索条文拼成最终推理 prompt。
- 参数：
  - `question`：用户问题。
  - `docs`：检索结果列表。
- 返回值：`str`，最终 prompt。
- 位置：`chatlaw/client/utils/common_utils.py:499`

### 37. `repl_inline`
- 作用：`render_mathml_from_latex` 的内部替换函数，用于处理行内公式。
- 参数：
  - `m`：正则匹配对象。
- 返回值：`str`，转换后的片段。
- 位置：`chatlaw/client/utils/common_utils.py:77`

### 38. `repl_block`
- 作用：`render_mathml_from_latex` 的内部替换函数，用于处理块级公式。
- 参数：
  - `m`：正则匹配对象。
- 返回值：`str`，转换后的片段。
- 位置：`chatlaw/client/utils/common_utils.py:83`

## 五、客户端网络工具

### 39. `heartbeat_client`
- 作用：PT 客户端的心跳线程，周期性发 `PING`，必要时发 `STOP`。
- 参数：
  - `server_ip`：服务端 IP。
  - `hb_port`：心跳端口。
  - `hb_interval`：心跳间隔。
  - `hb_timeout`：超时阈值。
  - `alive_flag`：存活状态回调。
  - `stop_event`：停止事件。
  - `recv_exact_fn`：精确读取函数。
- 返回值：无显式返回，线程函数。
- 位置：`chatlaw/client/utils/utils_pt.py:8`

### 40. `stream_from_server`
- 作用：PT 客户端的数据流接收器，向服务端发送模型输入并逐块接收输出。
- 参数：
  - `server_ip`：服务端 IP。
  - `data_port`：数据端口。
  - `handshake_req`：握手请求。
  - `handshake_resp`：握手响应。
  - `recv_exact_fn`：精确读取函数。
  - `alive_flag`：存活状态回调。
  - `stop_event`：停止事件。
  - `input_tensor`：模型输入张量。
- 返回值：生成器，逐块 `yield` 文本、`<END>` 或 `[ClientError] ...`。
- 位置：`chatlaw/client/utils/utils_pt.py:85`

### 41. `heartbeat_client_ms`
- 作用：MS 客户端的心跳线程，职责与 PT 版一致。
- 参数：
  - `server_ip`：服务端 IP。
  - `hb_port`：心跳端口。
  - `hb_interval`：心跳间隔。
  - `hb_timeout`：超时阈值。
  - `alive_flag`：存活状态回调。
  - `stop_event`：停止事件。
  - `recv_exact_fn`：精确读取函数。
- 返回值：无显式返回，线程函数。
- 位置：`chatlaw/client/utils/utils_ms.py:6`

### 42. `stream_from_server_ms`
- 作用：MS 客户端的数据流接收器，职责与 PT 版一致。
- 参数：
  - `server_ip`：服务端 IP。
  - `data_port`：数据端口。
  - `handshake_req`：握手请求。
  - `handshake_resp`：握手响应。
  - `recv_exact_fn`：精确读取函数。
  - `stop_event`：停止事件。
  - `input_tensor`：模型输入张量。
- 返回值：生成器，逐块 `yield` 文本、`<END>` 或 `[ClientError] ...`。
- 位置：`chatlaw/client/utils/utils_ms.py:82`
