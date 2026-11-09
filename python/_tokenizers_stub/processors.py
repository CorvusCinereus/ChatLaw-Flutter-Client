# coding: utf-8
"""tokenizers.processors 桩。"""


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


class Processor(_Stub):
    pass


class TemplateProcessing(_Stub):
    pass


class BertProcessing(_Stub):
    pass


class ByteLevel(_Stub):
    pass


class PostProcessor(_Stub):
    pass
