# coding: utf-8
"""tokenizers.implementations 桩（transformers 可能引用 BaseTokenizer）。"""


class _Stub:
    __slots__ = ()

    def __init__(self, *args, **kwargs):
        pass

    def __call__(self, *args, **kwargs):
        return self

    def __getattr__(self, name):
        def _noop(*a, **k):
            return None

        return _noop


class BaseTokenizer(_Stub):
    pass


class BertWordPieceTokenizer(_Stub):
    pass


class ByteLevelBPETokenizer(_Stub):
    pass


class CharBPETokenizer(_Stub):
    pass


class SentencePieceBPETokenizer(_Stub):
    pass


class SentencePieceUnigramTokenizer(_Stub):
    pass
