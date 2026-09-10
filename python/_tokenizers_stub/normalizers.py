# coding: utf-8
"""tokenizers.normalizers 桩。"""


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


class Normalizer(_Stub):
    pass


class Sequence(_Stub):
    pass


class NFD(_Stub):
    pass


class NFKC(_Stub):
    pass


class Lowercase(_Stub):
    pass


class Strip(_Stub):
    pass


class Replace(_Stub):
    pass


class BertNormalizer(_Stub):
    pass
