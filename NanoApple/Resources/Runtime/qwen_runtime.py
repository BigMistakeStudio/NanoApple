#!/usr/bin/env python3
"""Local Qwen-Image 2.1 runner used by NanoApple's bundled Swift interface."""

import argparse
import json
import os
import random
import sys
import tempfile
from pathlib import Path
from urllib.parse import unquote, urlparse


def write_status(path, progress=None, message=None):
    payload = {"progress": progress, "message": message}
    directory = os.path.dirname(path)
    fd, temporary = tempfile.mkstemp(prefix=".nanoapple-status-", suffix=".json", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--request", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--text-encoder")
    parser.add_argument("--viggle-turbo")
    args = parser.parse_args()

    with open(args.request, "r", encoding="utf-8") as handle:
        request = json.load(handle)

    write_status(args.status, 0.0, "Chargement de Qwen-Image 2.1")
    import torch
    from diffusers import FlowMatchEulerDiscreteScheduler, QwenImage21Pipeline
    from PIL import Image

    if not torch.backends.mps.is_available():
        raise RuntimeError("Le GPU Metal (MPS) n’est pas disponible.")

    metal_dtype = torch.float16
    pipeline_components = {}
    if args.text_encoder:
        from transformers import Qwen3VLForConditionalGeneration

        pipeline_components["text_encoder"] = Qwen3VLForConditionalGeneration.from_pretrained(
            args.text_encoder,
            dtype=torch.bfloat16,
            local_files_only=True,
        )

    pipe = QwenImage21Pipeline.from_pretrained(
        args.model,
        dtype={
            "text_encoder": torch.bfloat16,
            "transformer": metal_dtype,
            "vae": metal_dtype,
            "default": metal_dtype,
        },
        local_files_only=True,
        **pipeline_components,
    )
    if args.viggle_turbo:
        adapter = Path(args.viggle_turbo)
        if not adapter.is_file():
            raise FileNotFoundError(f"Adaptateur Viggle Turbo absent : {adapter}")
        pipe.load_lora_weights(str(adapter.parent), weight_name=adapter.name)
        pipe.scheduler = FlowMatchEulerDiscreteScheduler.from_config(
            pipe.scheduler.config, shift_terminal=None
        )
        print("NanoApple: Viggle Turbo activé (6 étapes, LoRA non fusionné).", flush=True)
    # Qwen3-VL currently triggers a fatal unaligned-buffer assertion in a
    # Metal concat kernel on Apple Silicon. Keep prompt/vision encoding on
    # CPU. PyTorch's MPS bfloat16 scalar kernels can also abort inside the
    # transformer and VAE, so run the Metal components and their embeddings
    # in float16 instead.
    pipe.transformer.to("mps")
    pipe.vae.to("mps")
    pipe.text_encoder.to("cpu")

    original_prompt_encoder = pipe._get_qwen_prompt_embeds

    def mps_safe_prompt_encoder(prompt, image=None, device=None):
        target_device = device or torch.device("mps")
        prompt_embeds, attention_mask, image_pad_mask = original_prompt_encoder(
            prompt,
            image,
            torch.device("cpu"),
        )
        prompt_embeds = prompt_embeds.to(device=target_device, dtype=metal_dtype)
        if attention_mask is not None:
            attention_mask = attention_mask.to(target_device)
        image_pad_mask = image_pad_mask.to(target_device)
        return prompt_embeds, attention_mask, image_pad_mask

    pipe._get_qwen_prompt_embeds = mps_safe_prompt_encoder
    pipe.enable_attention_slicing()
    print("NanoApple: Qwen3-VL bfloat16 sur CPU, transformeur et VAE float16 sur Metal.", flush=True)

    seed = random.SystemRandom().randrange(0, 2**31 - 1) if request["randomizeSeed"] else request["seed"]
    generator = torch.Generator(device="cpu").manual_seed(seed)
    prompt = request.get("enhancedPrompt") or request["prompt"]
    if request["mode"] == "transparentAsset":
        prompt = "This is an RGBA image with transparency. " + prompt + " The image has alpha channel and the background is transparent."

    steps = 6 if args.viggle_turbo else request["steps"]
    condition_images = []
    for reference in request.get("referenceImages", []):
        parsed = urlparse(reference)
        path = unquote(parsed.path) if parsed.scheme == "file" else reference
        condition_images.append(Image.open(Path(path)).convert("RGB"))
    if args.viggle_turbo and len(condition_images) > 3:
        raise ValueError("Viggle Turbo accepte au plus trois images de référence.")

    def on_step_end(_pipeline, index, _timestep, callback_kwargs):
        write_status(args.status, min((index + 1) / steps, 0.99), "Génération")
        return callback_kwargs

    write_status(args.status, 0.01, "Génération")
    resolution = request["resolution"]
    dimensions = {
        "square": (1024, 1024),
        "landscape": (1344, 768),
        "portrait": (768, 1344),
        "socialPortrait": (1024, 1280),
        "ultrawide": (1536, 672),
        "square2K": (2048, 2048),
        "landscape2K": (2048, 1152),
        "portrait2K": (1152, 2048),
    }
    if resolution == "custom":
        width = int(request.get("customWidth") or 1024)
        height = int(request.get("customHeight") or 1024)
    else:
        width, height = dimensions[resolution]

    if not (256 <= width <= 2048 and 256 <= height <= 2048 and width % 32 == 0 and height % 32 == 0):
        raise ValueError("La largeur et la hauteur doivent être comprises entre 256 et 2048 et divisibles par 32.")

    pipeline_arguments = dict(
        prompt=prompt,
        width=width,
        height=height,
        num_inference_steps=steps,
        generator=generator,
        callback_on_step_end=on_step_end,
        callback_on_step_end_tensor_inputs=[],
    )
    if args.viggle_turbo:
        pipeline_arguments["sigmas"] = [1.0, 0.9375, 0.875, 0.75, 0.5, 0.25]
        pipeline_arguments["true_cfg_scale"] = 1.0
    if condition_images:
        pipeline_arguments["image"] = condition_images
    negative_prompt = request.get("negativePrompt")
    if negative_prompt and not args.viggle_turbo:
        pipeline_arguments["negative_prompt"] = negative_prompt
        pipeline_arguments["true_cfg_scale"] = 4.0

    image = pipe(**pipeline_arguments).images[0]

    mask_reference = request.get("maskImage")
    if mask_reference and condition_images:
        parsed = urlparse(mask_reference)
        mask_path = unquote(parsed.path) if parsed.scheme == "file" else mask_reference
        source = condition_images[0].convert("RGBA").resize(image.size, Image.Resampling.LANCZOS)
        mask = Image.open(Path(mask_path)).convert("L").resize(image.size, Image.Resampling.LANCZOS)
        image = Image.composite(image.convert("RGBA"), source, mask)

    image.save(args.output)
    write_status(args.status, 1.0, "Terminé")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        raise
