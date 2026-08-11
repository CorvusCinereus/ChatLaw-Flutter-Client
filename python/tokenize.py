"""
分词模块。

将客户端流水线中的「分词」环节整理为独立模块：
- 所需逻辑（tokenizer 加载、chat 模板套用、分词）原样搬入本文件，
  不依赖原 ChatLaw 仓库代码，可独立运行。
- 资源（tokenizer）采用首次调用 run() 时懒加载并缓存，
  缺失时通过启智社区（openi）自动下载到 <仓库根>/resources/。
- 对外只暴露一个统一入口 run()，一次调用即可完成整个分词环节。

注：pt 客户端使用 PyTorch 张量（return_tensors="pt"），
    ms 客户端使用 NumPy 张量（return_tensors="np"），由 run() 参数区分。
"""

import os

from transformers import AutoTokenizer


def _get_resources_path():
    """
    返回资源目录。
    本文件位于 <仓库根>/python/，资源约定放在 <仓库根>/resources/。
    """
    return os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "resources",
    )


_TOKENIZER_FILES = [
    "merges.txt",
    "tokenizer.json",
    "tokenizer_config.json",
    "vocab.json",
]


def _files_complete(resource_dir, required_files):
    """检查资源目录是否存在且文件齐全。"""
    if not os.path.isdir(resource_dir):
        return False
    return all(
        os.path.isfile(os.path.join(resource_dir, name))
        for name in required_files
    )


def _download_tokenizer():
    """
    从启智社区（openi）下载 Qwen3 tokenizer。
    与原实现一致，tokenizer 文件下载到 resources/ 根目录；
    仅在文件不齐全时执行；openi 采用函数内延迟导入。
    """
    tokenizer_dir = os.path.join(_get_resources_path(), "tokenizer")
    if _files_complete(tokenizer_dir, _TOKENIZER_FILES):
        return
    import openi
    openi.openi_download_file(
        "enter/QwenTokenizer",
        repo_type="dataset",
        local_dir=_get_resources_path(),
        max_workers=10,
    )


_tokenizer = None


def _get_tokenizer():
    """
    懒加载 tokenizer。
    首次调用时确保资源已下载并初始化，之后直接复用缓存实例。
    """
    global _tokenizer
    if _tokenizer is None:
        _download_tokenizer()
        tokenizer_path = os.path.join(
            _get_resources_path(), "tokenizer"
        ).replace("\\", "/")
        _tokenizer = AutoTokenizer.from_pretrained(
            tokenizer_path, local_files_only=True
        )
    return _tokenizer


def run(final_prompt, return_tensors="pt"):
    """
    分词模块的统一入口，一次调用完成 chat 模板套用 + 分词。

    Args:
        final_prompt: 组装好的最终推理 prompt。
        return_tensors: 返回张量类型，pt 客户端传 "pt"，ms 客户端传 "np"。

    Returns:
        model_inputs: 可直接发送给服务端的模型输入。
    """
    tokenizer = _get_tokenizer()

    messages = [{"role": "user", "content": final_prompt}]
    templated = tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    return tokenizer([templated], return_tensors=return_tensors)


__all__ = [
    "run",
    "_get_tokenizer",
]
