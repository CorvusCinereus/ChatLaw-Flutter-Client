"""
Prompt 构建模块。

将客户端流水线中的「构建 prompt」环节整理为独立模块：
- 所需函数原样搬入本文件，不依赖原 ChatLaw 仓库代码，可独立运行。
- 本环节为纯字符串拼接，无资源加载。
- 对外只暴露一个统一入口 run()，一次调用即可完成整个构建环节。
"""


def _format_doc_block(item, idx: int):
    """
    兼容两种输入：
    1. FAISS 返回的 LangChain Document
    2. 精确索引返回的 dict
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

    # exact index dict
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


def run(question, docs):
    """
    Prompt 构建模块的统一入口，一次调用完成整个构建环节。

    Args:
        question: 用户咨询文本。
        docs: 知识库检索结果列表（FAISS Document 或精确索引 dict）。

    Returns:
        str: 组装好的最终推理 prompt。
    """
    return build_prompt(question, docs)


__all__ = [
    "run",
    "build_prompt",
    "_format_doc_block",
]
