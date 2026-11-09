"""
Prompt 构建模块。

将客户端流水线中的「构建 prompt」环节整理为独立模块：
- 所需函数原样搬入本文件，不依赖原 ChatLaw 仓库代码，可独立运行。
- 本环节为纯字符串拼接，无资源加载。
- 对外只暴露一个统一入口 main()：输入从 {APPDATA_DIR}/pipeline/rag_result.json
  读取，输出写入 {APPDATA_DIR}/pipeline/prompt.txt，供 tokenize.main() 经文件链读取。
"""

import os
import sys
import json


def _get_resources_path():
    """
    返回资源根目录。
    优先读取环境变量 APPDATA_DIR（由宿主 APP 传入）；
    未设置时回退到 <仓库根>/resources，便于独立运行与测试。
    """
    base = os.getenv("APPDATA_DIR")
    if base:
        return base
    return os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "resources",
    )


def _get_pipeline_dir():
    """
    返回流水线输出子目录：{资源根}/pipeline。
    """
    return os.path.join(_get_resources_path(), "pipeline")


def _format_doc_block(item, idx: int):
    """
    兼容两种输入：
    1. FAISS 返回的 LangChain Document
    2. 精确索引返回的 dict（含 rag_result.json 归一化记录）
    """
    # FAISS Document
    if hasattr(item, "metadata"):
        law_name = (
            item.metadata.get("law_name_raw")
            or item.metadata.get("law_name")
            or item.metadata.get("law_name_norm")
            or ""
        )
        article = item.metadata.get("article", "")
        content = item.metadata.get("content", "") or item.page_content
        return f"{idx}. 《{law_name}》{article}：\n{content}"

    # exact index dict / 归一化记录
    if isinstance(item, dict):
        law_name = (
            item.get("law_name_raw")
            or item.get("law_name")
            or item.get("law_name_norm")
            or ""
        )
        article = item.get("article", "")
        content = item.get("content", "")
        return f"{idx}. 《{law_name}》{article}：\n{content}"

    # fallback
    return f"{idx}. {str(item)}"


def build_prompt(question, docs):
    # 本模板是训练与推理的公共契约：develop/finetune/train_qwen3_finetune.py 直接复用
    # 桌面端 chatlaw/client/utils/common_utils.py 的同一实现生成训练数据，
    # 改动这里必须重新微调，否则训练/推理的输入分布会不一致。
    blocks = []

    for i, doc in enumerate(docs, 1):
        blocks.append(_format_doc_block(doc, i))

    context = "\n\n".join(blocks) if blocks else "（未检索到可用法律条文）"

    return f"""你是一个法律咨询专用模型。
你会遇到以下两种情况：
1. 用户的问题与法律条文无关。
2. 用户的问题与法律条文有关。

如果是情况1，则忽略法律条文，直接回答用户问题。
如果是情况2，请结合法律条文回答，并在回答结尾说明你的判断依据，具体到哪部法律及第几条。
如果当前没有检索到合适法条，不要编造法条内容，应基于常识谨慎回答，并明确说明“未检索到直接对应法条”。

【法律条文】（用户不可见）
{context}

【问题】
{question}

【回答】
"""


def main():
    """
    Prompt 构建模块的统一入口，一次调用完成整个构建环节。

    输入读取 {APPDATA_DIR}/pipeline/rag_result.json（由 rag.main() 生成）：
    question 取其中的 query 字段，docs 取归一化的 results 列表；
    输出写入 {APPDATA_DIR}/pipeline/prompt.txt。

    Returns:
        str: 组装好的最终推理 prompt。
    """
    in_path = os.path.join(_get_pipeline_dir(), "rag_result.json")
    if not os.path.isfile(in_path):
        print(f"[build] 缺少输入文件: {in_path}（请先运行 rag.main()）", file=sys.stderr)
        sys.exit(1)

    with open(in_path, "r", encoding="utf-8") as f:
        payload = json.load(f)

    question = payload.get("query", "")
    docs = payload.get("results", [])
    prompt = build_prompt(question, docs)

    out_path = os.path.join(_get_pipeline_dir(), "prompt.txt")
    try:
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(prompt)
    except Exception as e:
        print(f"[build] 保存 prompt 失败: {e}", file=sys.stderr)

    return prompt


if __name__ == "__main__":
    main()


__all__ = [
    "main",
    "build_prompt",
    "_format_doc_block",
]
