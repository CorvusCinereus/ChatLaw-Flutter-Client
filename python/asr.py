"""
语音转文字（ASR）模块。

将客户端流水线中的「语音转文字」环节整理为独立模块：
- 所需函数原样搬入本文件，不依赖原 ChatLaw 仓库代码，可独立运行。
- 资源（Paraformer 语音模型）采用首次调用 run() 时懒加载并缓存，
  缺失时通过启智社区（openi）自动下载到 <仓库根>/resources/。
- 对外只暴露一个统一入口 run()，一次调用即可完成整个 ASR 环节。
"""

import os
import time
import uuid

import numpy as np
import soundfile as sf
import librosa
from funasr_onnx import Paraformer


# ========== 模块级常量 ==========
TARGET_SR = 16000


def _get_resources_path():
    """
    返回资源目录。
    本文件位于 <仓库根>/python/，资源约定放在 <仓库根>/resources/。
    """
    return os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "resources",
    )


AUDIO_CACHE_DIR = os.path.join(_get_resources_path(), "_asr_cache")

_AUDIO_MODEL_FILES = [
    ".mdl", ".msc", ".mv", "am.mvn",
    "config.yaml", "configuration.json", "model_quant.onnx", "tokens.json",
]


def _files_complete(resource_dir, required_files):
    """检查资源目录是否存在且文件齐全。"""
    if not os.path.isdir(resource_dir):
        return False
    return all(
        os.path.isfile(os.path.join(resource_dir, name))
        for name in required_files
    )


def _download_audio_model():
    """
    从启智社区（openi）下载 Paraformer 语音模型到 resources/audio_model。
    仅在文件不齐全时执行；openi 采用函数内延迟导入，避免模块 import 即依赖。
    """
    audio_model_dir = os.path.join(_get_resources_path(), "audio_model")
    if _files_complete(audio_model_dir, _AUDIO_MODEL_FILES):
        return
    import openi
    openi.openi_download_file(
        "enter/Paraformer",
        repo_type="dataset",
        local_dir=audio_model_dir,
        max_workers=10,
    )


_audio_model = None


def _get_audio_model():
    """
    懒加载 Paraformer 语音识别模型。
    首次调用时确保资源已下载并初始化模型，之后直接复用缓存实例。
    """
    global _audio_model
    if _audio_model is None:
        _download_audio_model()
        audio_model_dir = os.path.join(
            _get_resources_path(), "audio_model"
        ).replace("\\", "/")
        os.makedirs(AUDIO_CACHE_DIR, exist_ok=True)
        _audio_model = Paraformer(
            audio_model_dir,
            batch_size=1,
            quantize=True,
            device_id=-1
        )
    return _audio_model


def speech_to_text(audio, target_sr, audio_cache_dir, audio_model):
    """
    audio: (sample_rate, numpy_array)
    return: 中文文本
    """
    if audio is None:
        return "未检测到语音输入"

    sr, data = audio

    # ---------- 1. 转单声道 ----------
    if data.ndim > 1:
        data = data.mean(axis=1)

    data = data.astype(np.float32)

    # ---------- 2. 重采样到 16k ----------
    if sr != target_sr:
        data = librosa.resample(data, orig_sr=sr, target_sr=target_sr)

    # ---------- 3. 幅值归一化（防止过小） ----------
    max_val = np.max(np.abs(data))
    if max_val > 0:
        data = data / max_val * 0.9

    # ---------- 4. 时长校验 ----------
    duration = len(data) / target_sr
    if duration < 0.8:
        return "语音过短，请说完整一句话"

    # ---------- 5. 写入固定目录 wav（避免 tempfile 坑） ----------
    wav_name = f"{uuid.uuid4().hex}.wav"
    wav_path = os.path.join(audio_cache_dir, wav_name)

    sf.write(wav_path, data, target_sr, subtype="PCM_16")

    # 确保文件完全落盘（Windows 必须）
    time.sleep(0.05)

    # ---------- 6. 调用 Paraformer ONNX ----------
    try:
        result = audio_model([wav_path])
    except Exception as e:
        return f"ASR 推理异常: {e}"
    finally:
        try:
            os.remove(wav_path)
        except Exception:
            pass

    # ---------- 7. 正确解析 funasr-onnx 返回 ----------
    # 返回格式示例：
    # [{'preds': ('如何理解等差数列', ['如','何','理','解','等','差','数','列'])}]
    if not result or not isinstance(result, list):
        return "未识别到有效内容"

    preds = result[0].get("preds", None)
    if not preds or not isinstance(preds, tuple):
        return "未识别到有效内容"

    text = preds[0].strip()
    if not text:
        raise ValueError("语音未识别到有效内容！")

    return text


def run(audio):
    """
    语音转文字模块的统一入口，一次调用完成整个 ASR 环节。

    Args:
        audio: (sample_rate, numpy_array)，来自麦克风输入的音频。

    Returns:
        str: 识别出的中文文本或错误提示。
    """
    return speech_to_text(
        audio=audio,
        target_sr=TARGET_SR,
        audio_cache_dir=AUDIO_CACHE_DIR,
        audio_model=_get_audio_model()
    )


__all__ = [
    "run",
    "speech_to_text",
    "TARGET_SR",
    "AUDIO_CACHE_DIR",
]
