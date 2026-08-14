"""
知识库检索（RAG）模块。

将客户端流水线中的「RAG 检索」环节整理为独立模块：
- 所需函数原样搬入本文件，不依赖原 ChatLaw 仓库代码，可独立运行。
- 资源（FAISS 向量库、精确索引、法条名候选）采用首次调用 run() 时懒加载并缓存，
  缺失时通过启智社区（openi）自动下载到资源根目录（APPDATA_DIR 或回退的 <仓库根>/resources/）。
- 对外只暴露一个统一入口 run()，一次调用即可完成整个检索环节。
"""

import os
import re
import json

from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import FAISS


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


_VECTORSTORE_FILES = [
    "law_article_index.json",
    "law_name_index.json",
    os.path.join("law_faiss", "index.faiss"),
    os.path.join("law_faiss", "index.pkl"),
    os.path.join("embedding_model", "1_Pooling", "config.json"),
    os.path.join("embedding_model", "config_sentence_transformers.json"),
    os.path.join("embedding_model", "gitattributes"),
    os.path.join("embedding_model", "modules.json"),
    os.path.join("embedding_model", "pytorch_model.bin"),
    os.path.join("embedding_model", "README.md"),
    os.path.join("embedding_model", "sentence_bert_config.json"),
    os.path.join("embedding_model", "special_tokens_map.json"),
    os.path.join("embedding_model", "tokenizer.json"),
    os.path.join("embedding_model", "tokenizer_config.json"),
    os.path.join("embedding_model", "vocab.txt"),
]


def _files_complete(resource_dir, required_files):
    """检查资源目录是否存在且文件齐全。"""
    if not os.path.isdir(resource_dir):
        return False
    return all(
        os.path.isfile(os.path.join(resource_dir, name))
        for name in required_files
    )


def _download_vectorstore():
    """
    从启智社区（openi）下载预构建向量库到资源根目录下的 vectorstore 子目录
    （{APPDATA_DIR}/vectorstore）。
    仅在文件不齐全时执行；openi 采用函数内延迟导入，避免模块 import 即依赖。
    """
    vectorstore_dir = os.path.join(_get_resources_path(), "vectorstore")
    if _files_complete(vectorstore_dir, _VECTORSTORE_FILES):
        return
    import openi
    openi.openi_download_file(
        "enter/vectorstore",
        repo_type="dataset",
        local_dir=vectorstore_dir,
        max_workers=10,
    )


_vectorstore = None
_exact_index = None
_law_name_candidates = None


def _get_resources():
    """
    懒加载检索所需资源（FAISS 向量库、精确索引、法条名候选）。
    首次调用时确保资源已下载并完成加载，之后直接复用缓存实例。
    """
    global _vectorstore, _exact_index, _law_name_candidates
    if _vectorstore is None:
        _download_vectorstore()
        _vectorstore = load_vectorstore(
            os.path.join(_get_resources_path(), "vectorstore", "law_faiss")
        )
        _exact_index = load_exact_index()
        _law_name_candidates = build_law_name_candidates(_exact_index)
    return _vectorstore, _exact_index, _law_name_candidates


def normalize_law_name(law_name: str) -> str:
    """
    统一法律名，便于精确匹配。
    例如：
    - 中华人民共和国公司法_20231229 -> 公司法
    - 公司法 -> 公司法
    """
    if not law_name:
        return ""

    s = law_name.strip()
    s = s.replace("《", "").replace("》", "")
    s = s.replace("中华人民共和国", "")
    s = re.sub(r"_[0-9]{8}$", "", s)
    s = re.sub(r"\s+", "", s)
    return s


def normalize_article_number(article_number: str) -> str:
    """
    统一条号格式。
    """
    if not article_number:
        return ""
    return re.sub(r"\s+", "", article_number.strip())


def match_law_name_from_query(query: str, law_name_candidates):
    """
    不再靠正则硬截法律名，而是：
    - 先标准化 query
    - 再在所有已知 law_name_norm 中找“最长子串匹配”
    """
    q = re.sub(r"\s+", "", query.strip())
    q = q.replace("《", "").replace("》", "")
    q = q.replace("中华人民共和国", "")

    for law_name in law_name_candidates:
        if law_name and law_name in q:
            return law_name

    return None


def parse_law_article_query(query: str, law_name_candidates=None):
    """
    尝试从 query 中解析：
    - 法律名
    - 条号

    适用于类似：
    - 公司法第五十八条的内容是什么？
    - 民法商法公司法第五十八条的内容是什么？
    """
    q = re.sub(r"\s+", "", query.strip())

    # 先提取条号
    m_article = re.search(r"(第[一二三四五六七八九十百千万零〇两\d]+条)", q)
    article = normalize_article_number(m_article.group(1)) if m_article else None

    # 再匹配法律名
    law_name = None
    if law_name_candidates:
        law_name = match_law_name_from_query(q, law_name_candidates)

    # 如果候选集合匹配不到，再兜底走旧正则
    if law_name is None:
        m = re.search(r"(?:民法商法)?(.+?法)(第[一二三四五六七八九十百千万零〇两\d]+条)", q)
        if m:
            law_name = normalize_law_name(m.group(1))

    return law_name, article


def load_vectorstore(path):
    embeddings = HuggingFaceEmbeddings(
        model_name=os.path.join(
            _get_resources_path(),
            "vectorstore",
            "embedding_model"
        ),
        encode_kwargs={"normalize_embeddings": True},
    )

    vectorstore = FAISS.load_local(
        path,
        embeddings,
        allow_dangerous_deserialization=True
    )
    return vectorstore


def load_exact_index(index_path=None):
    """
    加载精确索引。
    默认路径：
    {APPDATA_DIR}/vectorstore/law_article_index.json
    """
    if index_path is None:
        index_path = os.path.join(
            _get_resources_path(),
            "vectorstore",
            "law_article_index.json"
        )

    if not os.path.exists(index_path):
        raise FileNotFoundError(f"精确索引不存在: {index_path}")

    with open(index_path, "r", encoding="utf-8") as f:
        exact_index = json.load(f)

    return exact_index


def build_law_name_candidates(exact_index):
    """
    从精确索引中提取全部 law_name_norm，并按长度从长到短排序。
    这样做“最长子串匹配”更稳。
    """
    law_names = set()

    for _, item in exact_index.items():
        law_name_norm = item.get("law_name_norm", "")
        if law_name_norm:
            law_names.add(law_name_norm)

    return sorted(law_names, key=len, reverse=True)


def retrieve_laws_faiss(vectorstore, query, k=5):
    """
    走 FAISS 语义检索，返回 LangChain Document 列表
    """
    return vectorstore.similarity_search(query, k=k)


def retrieve_laws_exact(exact_index, query, law_name_candidates=None):
    """
    走精确索引检索。
    当前主要面向“某法第几条”的查询。
    返回统一格式的 dict 列表。
    """
    law_name, article = parse_law_article_query(
        query,
        law_name_candidates=law_name_candidates
    )

    if not law_name or not article:
        return []

    key = f"{law_name}::{article}"

    if key in exact_index:
        item = exact_index[key]
        return [item]

    return []


def _doc_unique_key(item):
    """
    用于 exact/faiss 混合后去重
    """
    if hasattr(item, "metadata"):
        law_name = (
            item.metadata.get("law_name_raw")
            or item.metadata.get("law_name")
            or item.metadata.get("law_name_norm")
            or ""
        )
        article = item.metadata.get("article", "")
        return f"{law_name}::{article}"

    if isinstance(item, dict):
        law_name = (
            item.get("law_name_raw")
            or item.get("law_name")
            or item.get("law_name_norm")
            or ""
        )
        article = item.get("article", "")
        return f"{law_name}::{article}"

    return str(item)


def merge_docs_keep_order(*doc_lists):
    """
    按顺序合并多个结果列表，并去重
    """
    merged = []
    seen = set()

    for docs in doc_lists:
        for doc in docs:
            key = _doc_unique_key(doc)
            if key not in seen:
                merged.append(doc)
                seen.add(key)

    return merged


def retrieve_laws(vectorstore,
                  query,
                  exact_index=None,
                  law_name_candidates=None,
                  exact_faiss_k=1,
                  faiss_only_k=5):
    """
    混合检索策略：

    1. 先尝试 exact
    2. 若 exact 命中：
       - 返回 1 条 exact
       - 再补 1 条 faiss 作为参考
    3. 若 exact 未命中：
       - 直接走 faiss，取 5 条

    这样可以兼顾：
    - 法条精确定位
    - 开放场景语义召回

    返回统一的 docs 列表，可直接传给 build_prompt。
    """
    exact_docs = []
    if exact_index is not None:
        exact_docs = retrieve_laws_exact(
            exact_index=exact_index,
            query=query,
            law_name_candidates=law_name_candidates
        )

    # exact 命中：1条 exact + 1条 faiss
    if exact_docs:
        faiss_docs = retrieve_laws_faiss(vectorstore, query, k=exact_faiss_k)
        return merge_docs_keep_order(exact_docs, faiss_docs)

    # exact 未命中：直接 faiss 5条
    return retrieve_laws_faiss(vectorstore, query, k=faiss_only_k)


def run(query, exact_faiss_k=1, faiss_only_k=5):
    """
    知识库检索模块的统一入口，一次调用完成整个 RAG 环节。

    Args:
        query: 用户咨询文本。
        exact_faiss_k: 精确命中时补充的 FAISS 条数。
        faiss_only_k: 未命中时直接 FAISS 的条数。

    Returns:
        list: 统一格式的检索结果（FAISS Document 或精确索引 dict），
              可直接传给 build.run() 构建 prompt。
    """
    vectorstore, exact_index, law_name_candidates = _get_resources()
    return retrieve_laws(
        vectorstore=vectorstore,
        query=query,
        exact_index=exact_index,
        law_name_candidates=law_name_candidates,
        exact_faiss_k=exact_faiss_k,
        faiss_only_k=faiss_only_k,
    )


__all__ = [
    "run",
    "normalize_law_name",
    "normalize_article_number",
    "match_law_name_from_query",
    "parse_law_article_query",
    "load_vectorstore",
    "load_exact_index",
    "build_law_name_candidates",
    "retrieve_laws_faiss",
    "retrieve_laws_exact",
    "merge_docs_keep_order",
    "retrieve_laws",
]
