# coding: utf-8
"""tokenizers.models 桩。"""


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


class BPE(_Stub):
    pass


class Unigram(_Stub):
    pass


class WordPiece(_Stub):
    pass


class WordLevel(_Stub):
    pass


class Model(_Stub):
    pass
