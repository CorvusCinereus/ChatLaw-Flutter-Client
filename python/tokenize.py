"""
分词模块。

将客户端流水线中的「分词」环节整理为独立模块：
- 所需逻辑（tokenizer 加载、chat 模板套用、分词）原样搬入本文件，
  不依赖原 ChatLaw 仓库代码，可独立运行。
- 资源（tokenizer）采用首次调用 run() 时懒加载并缓存，
  缺失时通过启智社区（openi）自动下载到资源根目录（APPDATA_DIR 或回退的 <仓库根>/resources/）。
- 对外只暴露一个统一入口 run()，一次调用即可完成整个分词环节。

注：pt 客户端使用 PyTorch 张量（return_tensors="pt"），
    ms 客户端使用 NumPy 张量（return_tensors="np"），由 run() 参数区分。
"""

import os
import sys
import pickle

from transformers import AutoTokenizer


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
    与原实现一致，tokenizer 文件下载到资源根目录（{APPDATA_DIR}/）；
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
            tokenizer_path, use_fast=False, local_files_only=True
        )
    return _tokenizer


def main():
    """
    分词模块的统一入口，一次调用完成 chat 模板套用 + 分词。

    输入读取 {APPDATA_DIR}/pipeline/prompt.txt（由 build.main() 生成）；
    输出以 pickle 序列化写入 {APPDATA_DIR}/pipeline/model_inputs.pkl
    （return_tensors 固定为 "pt"，对应 Transformers 服务端）。

    Returns:
        model_inputs: 可直接发送给服务端的模型输入。
    """
    in_path = os.path.join(_get_pipeline_dir(), "prompt.txt")
    if not os.path.isfile(in_path):
        print(f"[tokenize] 缺少输入文件: {in_path}（请先运行 build.main()）", file=sys.stderr)
        sys.exit(1)

    with open(in_path, "r", encoding="utf-8") as f:
        final_prompt = f.read()

    tokenizer = _get_tokenizer()

    messages = [{"role": "user", "content": final_prompt}]
    templated = tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    # return_tensors="np"：Android 环境无 torch（Android 端不安装 torch），
    # 用 numpy 张量（BatchEncoding），服务端 pickle.load 后可正常读取 input_ids 等。
    model_inputs = tokenizer([templated], return_tensors="np")

    out_path = os.path.join(_get_pipeline_dir(), "model_inputs.pkl")
    try:
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "wb") as f:
            pickle.dump(model_inputs, f)
    except Exception as e:
        print(f"[tokenize] 保存 model_inputs 失败: {e}", file=sys.stderr)

    return model_inputs


if __name__ == "__main__":
    main()


__all__ = [
    "main",
    "_get_tokenizer",
]
