# coding: utf-8
"""tokenizers.trainers 桩。"""


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


class Trainer(_Stub):
    pass


class BpeTrainer(_Stub):
    pass


class UnigramTrainer(_Stub):
    pass


class WordLevelTrainer(_Stub):
    pass


class WordPieceTrainer(_Stub):
    pass
