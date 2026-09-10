# coding: utf-8
"""tokenizers.pre_tokenizers 桩。"""


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


class PreTokenizer(_Stub):
    pass


class BertPreTokenizer(_Stub):
    pass


class ByteLevel(_Stub):
    pass


class Whitespace(_Stub):
    pass


class WhitespaceSplit(_Stub):
    pass


class Split(_Stub):
    pass


class Metaspace(_Stub):
    pass


class Sequence(_Stub):
    pass


class Punctuation(_Stub):
    pass


class Digits(_Stub):
    pass
