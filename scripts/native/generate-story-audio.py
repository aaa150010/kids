"""Author-time Qwen narration. Does not build/export the APK or contact the release server."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import shutil

ROOT = Path(__file__).resolve().parents[2]
os.environ.setdefault("HF_HOME", str(ROOT / "build/story-tools/huggingface"))
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description="使用 Qwen3-TTS 制作普通话故事音频，支持中断后继续。")
    parser.add_argument("--backend", choices=["mlx", "torch"], default="mlx")
    parser.add_argument("--model", default=None)
    parser.add_argument("--speaker", default="Serena")
    parser.add_argument("--revision", default="6415d95f88be018ff9e46813119dc3bc12261328")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--category", default="")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--batch-size", type=int, default=8)
    args = parser.parse_args()
    import numpy as np
    import soundfile as sf
    import imageio_ffmpeg

    all_stories = json.loads((ROOT / "content-src/data/stories.json").read_text())
    catalog = all_stories
    if args.category:
        catalog = [story for story in catalog if story["category"] == args.category]
    index_path = ROOT / "content-src/data/story-audio.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else {"schema": 1, "assets": {}}
    current_hashes = {story["id"]: story["narrationSha256"] for story in all_stories}
    index["assets"] = {key: value for key, value in index["assets"].items() if current_hashes.get(key) == value.get("textSha256")}
    for entry in index["assets"].values():
        entry.setdefault("generator", {})["revision"] = args.revision
    output = ROOT / "content-src/story-audio/audio"
    output.mkdir(parents=True, exist_ok=True)
    work = ROOT / "build/story-audio-work"
    work.mkdir(parents=True, exist_ok=True)
    segment_cache = work / "paragraphs"

    def validate_library():
        invalid = []
        for story in all_stories:
            entry = index["assets"].get(story["id"])
            if not entry or entry.get("textSha256") != story["narrationSha256"]:
                invalid.append(story["title"])
                continue
            timeline = entry.get("paragraphs", [])
            if len(timeline) != len(story["paragraphs"]):
                invalid.append(story["title"])
                continue
            previous_end = 0.0
            invalid_timeline = False
            for segment in timeline:
                if segment.get("start", 0.0) < previous_end or segment.get("end", 0.0) <= segment.get("start", 0.0):
                    invalid_timeline = True
                    break
                previous_end = segment["end"]
            if invalid_timeline or previous_end > entry.get("duration", 0.0) + 0.01:
                invalid.append(story["title"])
                continue
            audio_path = output / Path(entry["url"]).name
            if (
                not audio_path.exists()
                or audio_path.stat().st_size != entry["size"]
                or hashlib.sha256(audio_path.read_bytes()).hexdigest() != entry["sha256"]
            ):
                invalid.append(story["title"])
        if invalid:
            raise RuntimeError("故事音频索引不完整：" + "、".join(invalid[:5]))

    def cleanup_artifacts():
        if segment_cache.exists():
            shutil.rmtree(segment_cache)
        referenced = {Path(entry["url"]).name for entry in index["assets"].values()}
        for path in output.glob("*.mp3"):
            if path.name not in referenced:
                path.unlink()
        for path in output.glob("*.tmp"):
            path.unlink()
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    model_id = args.model or ("mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16" if args.backend == "mlx" else "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice")
    pending = []
    for story in catalog:
        previous = index["assets"].get(story["id"], {})
        filename = output / (previous.get("sha256", "missing") + ".mp3")
        if not args.force and previous.get("textSha256") == story["narrationSha256"] and filename.exists():
            if hashlib.sha256(filename.read_bytes()).hexdigest() == previous.get("sha256"):
                continue
        pending.append(story)
    if args.limit:
        pending = pending[:args.limit]
    if not pending:
        atomic_json(index_path, index)
        atomic_json(ROOT / "apps/android/content/story-audio.json", index)
        if not args.category and not args.limit:
            validate_library()
        print("当前故事的音频已经制作完成。", flush=True)
        cleanup_artifacts()
        return
    segment_cache.mkdir(parents=True, exist_ok=True)
    profile = f"{args.backend}:{model_id}:{args.speaker}:v1"
    plans, jobs, known_jobs = {}, [], set()
    for story in pending:
        texts = [story["title"] + "。"] + [paragraph["text"] for paragraph in story["paragraphs"]]
        parts = []
        for text in texts:
            key = hashlib.sha256((profile + "\n" + text).encode()).hexdigest()
            path = segment_cache / (key + ".wav")
            if args.force and path.exists():
                path.unlink()
            parts.append(path)
            if not path.exists() and key not in known_jobs:
                known_jobs.add(key)
                jobs.append({"path": path, "text": text, "storyId": story["id"]})
        plans[story["id"]] = {"story": story, "parts": parts}

    if args.backend == "mlx":
        from mlx_audio.tts.utils import load_model
        import mlx.core as mx
        from huggingface_hub import snapshot_download
        model_source = snapshot_download(repo_id=model_id, revision=args.revision)
        model = load_model(model_source)

        def synthesize_many(texts):
            generated = {}
            for result in model.batch_generate(texts=texts, voices=[args.speaker] * len(texts), lang_code="Chinese", max_tokens=2048, temperature=0.7):
                generated[int(result.sequence_idx)] = (np.asarray(result.audio).reshape(-1), int(result.sample_rate))
            mx.clear_cache()
            return [generated[index] for index in range(len(texts))]
    else:
        import torch
        from qwen_tts import Qwen3TTSModel
        device = "cuda:0" if torch.cuda.is_available() else "cpu"
        model = Qwen3TTSModel.from_pretrained(model_id, device_map=device, dtype=torch.bfloat16 if device != "cpu" else torch.float32)

        def synthesize_many(texts):
            wavs, sample_rate = model.generate_custom_voice(text=texts, speaker=[args.speaker] * len(texts), language=["Chinese"] * len(texts))
            return [(np.asarray(wav).reshape(-1), int(sample_rate)) for wav in wavs]

    completed = set()

    def assemble(story_id):
        if story_id in completed:
            return
        plan = plans[story_id]
        if not all(path.exists() for path in plan["parts"]):
            return
        story = plan["story"]
        clips, timeline = [], []
        cursor = 0.0
        rate = None
        for paragraph_number, path in enumerate(plan["parts"]):
            samples, sample_rate = sf.read(path, dtype="float32")
            if rate is not None and sample_rate != rate:
                raise RuntimeError("同一故事的音频采样率发生变化。")
            rate = sample_rate
            start = cursor
            silence = np.zeros(int(rate * 0.3), dtype=np.float32)
            clips.extend([samples, silence])
            cursor += (len(samples) + len(silence)) / rate
            if paragraph_number > 0:
                timeline.append({"start": round(start, 3), "end": round(cursor, 3)})
        combined = np.concatenate(clips)
        combined = combined / max(1.0, float(np.max(np.abs(combined))) / 0.95)
        with tempfile.TemporaryDirectory(prefix="story-", dir=work) as folder:
            wav_path = Path(folder) / "narration.wav"
            mp3_path = Path(folder) / "narration.mp3"
            sf.write(wav_path, combined, rate)
            subprocess.run([ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav_path), "-af", "loudnorm=I=-18:TP=-2:LRA=7", "-ar", "24000", "-ac", "1", "-codec:a", "libmp3lame", "-b:a", "48k", str(mp3_path)], check=True)
            data = mp3_path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            destination = output / (digest + ".mp3")
            existing_is_valid = (
                destination.exists()
                and destination.stat().st_size == len(data)
                and hashlib.sha256(destination.read_bytes()).hexdigest() == digest
            )
            if not existing_is_valid:
                temporary_audio = destination.with_suffix(".tmp")
                temporary_audio.write_bytes(data)
                temporary_audio.replace(destination)
        index["assets"][story["id"]] = {
            "url": f"audio/{digest}.mp3", "sha256": digest, "size": len(data),
            "duration": round(cursor, 3), "textSha256": story["narrationSha256"], "paragraphs": timeline,
            "generator": {"model": model_id, "revision": args.revision, "speaker": args.speaker, "backend": args.backend},
        }
        atomic_json(index_path, index)
        atomic_json(ROOT / "apps/android/content/story-audio.json", index)
        completed.add(story_id)
        print(f"[{len(completed)}/{len(pending)}] 已保存：{story['title']}（{len(data)} 字节）", flush=True)

    for story_id in plans:
        assemble(story_id)
    batch_size = max(1, min(args.batch_size, 16))
    for start in range(0, len(jobs), batch_size):
        batch = jobs[start:start + batch_size]
        print(f"制作段落 {start + 1}–{start + len(batch)}/{len(jobs)}", flush=True)
        results = synthesize_many([job["text"] for job in batch])
        for job, (samples, sample_rate) in zip(batch, results, strict=True):
            if samples.size == 0 or not np.isfinite(samples).all():
                raise RuntimeError(f"音频生成失败：{job['text'][:24]}")
            temporary = job["path"].with_suffix(".tmp.wav")
            sf.write(temporary, samples, sample_rate)
            temporary.replace(job["path"])
        for story_id in plans:
            assemble(story_id)
    if len(completed) != len(pending):
        raise RuntimeError("仍有未完成的故事音频；再次运行可从已生成段落继续。")
    if not args.category and not args.limit:
        validate_library()
    cleanup_artifacts()
    print(f"本轮完成 {len(completed)} 篇，书库已有 {len(index['assets'])} 篇音频。", flush=True)


if __name__ == "__main__":
    main()
