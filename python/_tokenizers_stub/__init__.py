# coding: utf-8
"""纯 Python 桩 tokenizers 包。

背景：serious_python 从 pypi.flet.dev 拉到的 tokenizers 原生库（lib/arm64/libtokenizers-
tokenizers.so）虽然在 wheel 里标记为 cp39-abi3（稳定 ABI），但实际动态链接依赖
libpython3.12.so，与本环境内嵌的 Python 3.14 不兼容，一旦真正 import 就会 dlopen 失败。

而 transformers 在 import 阶段（integrations/ggml.py、convert_slow_tokenizer.py、
tokenization_utils_fast.py 等）会"无条件" `from tokenizers import Tokenizer, decoders,
models.BPE, ...`，因此 tokenizers 必须能成功 import，否则整个 transformers 都加载失败。

我们实际分词既不依赖本包：向量嵌入用 transformers 的**慢速**分词器（use_fast=False），
chat 模板分词同样走慢速路径。本 stub 仅提供可 import、可 isinstance 的占位类，让
transformers 能完成加载；tokenizers 的真实能力（encode 等）在本管线中不会被执行。

注意：本包是纯 Python，不含任何原生 .so。
"""

from __future__ import annotations

__version__ = "0.22.2-stub"

from . import decoders, models, normalizers, pre_tokenizers, processors, trainers
from . import implementations  # noqa: F401  # 触发子模块注册，保持 import 语义
from .implementations import (  # noqa: F401
    BaseTokenizer,
    BertWordPieceTokenizer,
    ByteLevelBPETokenizer,
    CharBPETokenizer,
    SentencePieceBPETokenizer,
    SentencePieceUnigramTokenizer,
)


class Offsets:  # 占位命名空间替代原 tuple 别名（transformers 不依赖其构造）
    pass


class TextInputSequence:  # noqa: N801 保留命名，占位
    pass


class _Stub:
    """基础占位：可实例化、可作为基类，属性缺失时显式报错（避免静默返回函数污染数据）。"""

    __slots__ = ()

    def __init__(self, *args, **kwargs):
        pass

    def __call__(self, *args, **kwargs):
        return self


class AddedToken:
    """与 transformers 期望的 AddedToken 协议一致的真实最小实现。

    transformers 会在 `is_tokenizers_available()` 为真时直接使用本类（而非其内部
    fallback 的 AddedToken），并通过 `.content`、`.special`、`.normalized`、`__getstate__`/
    `__setstate__` 等协议操作。若本类过于"空"（例如 `__getattr__` 返回函数），则
    `AddedToken(...).content` 会得到函数对象，进而污染 `added_tokens_encoder` 的 key，
    导致 `dict(vocab, **encoder)` 抛 `TypeError: keywords must be strings`。
    因此这里实现完整的字段与序列化协议，保证特殊 token 的 content 始终是字符串。
    """

    def __init__(self, content, single_word=False, lstrip=False, rstrip=False,
                 special=False, normalized=None):
        self.content = content
        self.single_word = single_word
        self.lstrip = lstrip
        self.rstrip = rstrip
        self.special = special
        self.normalized = normalized if normalized is not None else not special

    def __getstate__(self):
        return self.__dict__

    def __setstate__(self, state):
        self.__dict__.update(state)

    def __repr__(self):
        return f"AddedToken({self.content!r}, special={self.special})"

    def __eq__(self, other):
        if isinstance(other, AddedToken):
            return self.content == other.content and self.special == other.special
        return NotImplemented

    def __hash__(self):
        return hash((self.content, self.special))

    def __str__(self):
        return self.content


class Tokenizer(_Stub):
    pass


class Regex(_Stub):
    pass


class Encoding(_Stub):
    pass


class NormalizedString(_Stub):
    pass


class PreTokenizedString(_Stub):
    pass


class CharBPETokenizer(_Stub):
    pass


class Decoder(_Stub):
    pass


class PreTokenizer(_Stub):
    pass
