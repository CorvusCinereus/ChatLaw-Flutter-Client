# coding: utf-8
"""tokenizers.decoders 桩。"""


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


class Decoder(_Stub):
    pass


class DecodeStream(_Stub):
    pass


class ByteLevel(_Stub):
    pass


class Metaspace(_Stub):
    pass


class Fuse(_Stub):
    pass


class CTC(_Stub):
    pass


class Sequence(_Stub):
    pass


class Replace(_Stub):
    pass


class WordPiece(_Stub):
    pass
