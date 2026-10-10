#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
# SPDX-License-Identifier: GPL-3.0-only

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


def load_consistency_lora(pipe, adapter_path):
    """Map the ComfyUI Qwen 2.1 LoRA to Diffusers' unfused SwiGLU layers."""
    from safetensors.torch import load_file

    weights = load_file(str(adapter_path), device="cpu")
    converted = {}
    expected = set()
    dtype = pipe.transformer.dtype

    def add_pair(block_index, source_name, target_name, module):
        source = f"diffusion_model.transformer_blocks.{block_index}.{source_name}"
        target = f"transformer.transformer_blocks.{block_index}.{target_name}"
        a_key = f"{source}.lora_A.weight"
        b_key = f"{source}.lora_B.weight"
        expected.update((a_key, b_key))
        a = weights[a_key]
        b = weights[b_key]
        rank = a.shape[0]
        if tuple(a.shape) != (rank, module.in_features) or tuple(b.shape) != (module.out_features, rank):
            raise ValueError(f"Dimensions LoRA incompatibles : {source_name}, bloc {block_index}")
        converted[f"{target}.lora_A.weight"] = a.to(dtype=dtype)
        converted[f"{target}.lora_B.weight"] = b.to(dtype=dtype)

    for index, block in enumerate(pipe.transformer.transformer_blocks):
        for name, module in (
            ("to_q", block.attn.to_q),
            ("to_k", block.attn.to_k),
            ("to_v", block.attn.to_v),
            ("to_out.0", block.attn.to_out[0]),
        ):
            add_pair(index, f"attn.{name}", f"attn.{name}", module)
        add_pair(index, "img_mlp.out", "img_mlp.out", block.img_mlp.out)

        source = f"diffusion_model.transformer_blocks.{index}.img_mlp.gate_up"
        a_key = f"{source}.lora_A.weight"
        b_key = f"{source}.lora_B.weight"
        expected.update((a_key, b_key))
        a = weights[a_key]
        b = weights[b_key]
        rank = a.shape[0]
        gate = block.img_mlp.gate_layer
        up = block.img_mlp.proj
        if (gate.in_features != up.in_features
                or tuple(a.shape) != (rank, gate.in_features)
                or tuple(b.shape) != (gate.out_features + up.out_features, rank)):
            raise ValueError(f"Dimensions SwiGLU incompatibles dans le bloc {index}")
        gate_b, up_b = b.split((gate.out_features, up.out_features), dim=0)
        for name, part in (("gate_layer", gate_b), ("proj", up_b)):
            target = f"transformer.transformer_blocks.{index}.img_mlp.{name}"
            converted[f"{target}.lora_A.weight"] = a.to(dtype=dtype)
            converted[f"{target}.lora_B.weight"] = part.to(dtype=dtype)

    if set(weights) != expected:
        raise ValueError("La LoRA de cohérence contient des tenseurs manquants ou inattendus.")
    pipe.load_lora_weights(converted, adapter_name="consistency")


def load_viewpoint_orbit_lora(pipe, adapter_path):
    """Load every split Orbit weight explicitly, without ComfyUI key conversion."""
    from safetensors.torch import load_file

    weights = load_file(str(adapter_path), device="cpu")
    converted = {}
    expected = set()
    for index, block in enumerate(pipe.transformer.transformer_blocks):
        modules = {
            "attn.to_q": block.attn.to_q,
            "attn.to_k": block.attn.to_k,
            "attn.to_v": block.attn.to_v,
            "attn.to_out.0": block.attn.to_out[0],
            "img_mlp.gate_layer": block.img_mlp.gate_layer,
            "img_mlp.proj": block.img_mlp.proj,
            "img_mlp.out": block.img_mlp.out,
        }
        for name, module in modules.items():
            source = f"diffusion_model.transformer_blocks.{index}.{name}"
            target = f"transformer.transformer_blocks.{index}.{name}"
            for branch, shape in (("A", (32, module.in_features)),
                                  ("B", (module.out_features, 32))):
                key = f"{source}.lora_{branch}.weight"
                expected.add(key)
                if key not in weights or tuple(weights[key].shape) != shape:
                    raise ValueError(f"Poids Viewpoint Orbit absent ou incompatible : {key}")
                converted[f"{target}.lora_{branch}.weight"] = weights[key].to(
                    dtype=pipe.transformer.dtype
                )
    if set(weights) != expected:
        raise ValueError("Viewpoint Orbit contient des tenseurs inattendus ; utilisez le fichier gate_up_split.")
    pipe.load_lora_weights(converted, adapter_name="viewpoint_orbit")
    print(f"NanoApple: Viewpoint Orbit chargé intégralement ({len(converted)} tenseurs).", flush=True)


def orbit_prompt(request):
    rotations = {
        "left45": "rotate the camera 45 degrees to the left",
        "left90": "rotate the camera 90 degrees to the left",
        "left135": "rotate the camera 135 degrees to the left",
        "right45": "rotate the camera 45 degrees to the right",
        "right90": "rotate the camera 90 degrees to the right",
        "right135": "rotate the camera 135 degrees to the right",
        "halfTurn": "rotate the camera 180 degrees",
        "keepAngle": "keep the camera angle",
    }
    elevations = {"lowAngle": "low angle", "eyeLevel": "eye level", "elevated": "elevated"}
    settings = request.get("viewpointOrbit") or {}
    rotation, elevation = settings.get("rotation"), settings.get("elevation")
    if (rotation not in rotations or elevation not in elevations
            or (rotation == "keepAngle" and elevation == "eyeLevel")):
        raise ValueError("Choisissez une rotation et une hauteur de caméra prises en charge par Viewpoint Orbit.")
    return (f"<orbit> {rotations[rotation]}, {elevations[elevation]}. "
            "The image has alpha channel and the background is transparent.")


def validate_orbit_request(request, args):
    is_orbit = request["mode"] == "viewpointOrbit"
    if is_orbit != bool(args.viewpoint_orbit):
        raise ValueError("Le mode Angle de vue demande l’adaptateur Viewpoint Orbit.")
    if not is_orbit:
        return
    orbit_prompt(request)
    if (args.viggle_turbo or args.consistency_lora or args.text_encoder
            or request.get("useViggleTurbo") or request.get("useConsistencyLoRA")
            or request.get("backend") not in (None, "diffusers")
            or request.get("enhancePrompt") or request.get("enhancedPrompt") is not None
            or request.get("maskImage") is not None
            or len(request.get("referenceImages", [])) != 1
            or request.get("steps") != 40 or request.get("resolution") != "custom"
            or request.get("customWidth") != 768 or request.get("customHeight") != 768):
        raise ValueError("Viewpoint Orbit demande le modèle complet, une référence transparente, 768 × 768 et 40 étapes, sans autre adaptateur ni masque.")


def load_orbit_reference(reference):
    from PIL import Image, ImageOps

    parsed = urlparse(reference)
    path = unquote(parsed.path) if parsed.scheme == "file" else reference
    with Image.open(Path(path)) as source:
        image = ImageOps.exif_transpose(source).convert("RGBA")
    alpha_min, alpha_max = image.getchannel("A").getextrema()
    if alpha_min == 255 or alpha_max == 0:
        raise ValueError("Ajoutez une image avec un sujet visible et un fond réellement transparent. Vous pouvez la préparer en mode PNG transparent.")
    # Fit and pad rather than stretching a non-square product reference.
    fitted = ImageOps.contain(image, (768, 768), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (768, 768), (0, 0, 0, 0))
    canvas.paste(fitted, ((768 - fitted.width) // 2, (768 - fitted.height) // 2))
    return canvas


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--request", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--text-encoder")
    parser.add_argument("--official-turbo", action="store_true")
    parser.add_argument("--viggle-turbo")
    parser.add_argument("--consistency-lora")
    parser.add_argument("--viewpoint-orbit")
    args = parser.parse_args()

    with open(args.request, "r", encoding="utf-8") as handle:
        request = json.load(handle)
    validate_orbit_request(request, args)
    if args.official_turbo and (args.text_encoder or args.viggle_turbo
                               or args.consistency_lora or args.viewpoint_orbit
                               or request.get("mode") == "viewpointOrbit"
                               or request.get("useViggleTurbo")
                               or request.get("useConsistencyLoRA")):
        raise ValueError("Le modèle Turbo officiel ne se combine pas avec ces adaptateurs.")
    orbit_reference = None
    if args.viewpoint_orbit:
        if not Path(args.viewpoint_orbit).is_file():
            raise FileNotFoundError(f"Adaptateur Viewpoint Orbit absent : {args.viewpoint_orbit}")
        # Reject opaque inputs before allocating the large model on Metal.
        orbit_reference = load_orbit_reference(request["referenceImages"][0])
    if args.consistency_lora and (args.viggle_turbo or request["mode"] != "edit"
                                  or len(request.get("referenceImages", [])) != 1):
        raise ValueError("Consistency LoRA demande une retouche avec une seule image de référence, sans Viggle Turbo.")

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
    if args.official_turbo:
        schedule = getattr(pipe.config, "sample_sigmas", None)
        if schedule is None or len(schedule) != 8:
            raise RuntimeError("Le modèle Turbo demande son calendrier officiel de 8 étapes ; réinstallez le runtime et vérifiez les poids.")
        print("NanoApple: Turbo officiel activé (8 étapes, CFG 1, cache KV).", flush=True)
    if args.viggle_turbo:
        adapter = Path(args.viggle_turbo)
        if not adapter.is_file():
            raise FileNotFoundError(f"Adaptateur Viggle Turbo absent : {adapter}")
        pipe.load_lora_weights(str(adapter.parent), weight_name=adapter.name)
        pipe.scheduler = FlowMatchEulerDiscreteScheduler.from_config(
            pipe.scheduler.config, shift_terminal=None
        )
        print("NanoApple: Viggle Turbo activé (6 étapes, LoRA non fusionné).", flush=True)
    if args.consistency_lora:
        adapter = Path(args.consistency_lora)
        if not adapter.is_file():
            raise FileNotFoundError(f"Adaptateur Consistency LoRA absent : {adapter}")
        load_consistency_lora(pipe, adapter)
        print("NanoApple: Consistency LoRA activée pour la retouche.", flush=True)
    if args.viewpoint_orbit:
        load_viewpoint_orbit_lora(pipe, Path(args.viewpoint_orbit))
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
    if args.viewpoint_orbit:
        prompt = orbit_prompt(request)
    if request["mode"] == "transparentAsset":
        prompt = "This is an RGBA image with transparency. " + prompt + " The image has alpha channel and the background is transparent."

    steps = 8 if args.official_turbo else (40 if args.viewpoint_orbit else (6 if args.viggle_turbo else request["steps"]))
    condition_images = [orbit_reference] if orbit_reference is not None else []
    for reference in ([] if args.viewpoint_orbit else request.get("referenceImages", [])):
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
    if args.official_turbo:
        pipeline_arguments["true_cfg_scale"] = 1.0
        pipeline_arguments["use_kv_cache"] = True
    if args.viggle_turbo:
        pipeline_arguments["sigmas"] = [1.0, 0.9375, 0.875, 0.75, 0.5, 0.25]
        pipeline_arguments["true_cfg_scale"] = 1.0
    if args.consistency_lora:
        pipeline_arguments["true_cfg_scale"] = 1.0
    if args.viewpoint_orbit:
        pipeline_arguments["true_cfg_scale"] = 1.0
        # Diffusers resizes references separately from the output dimensions.
        pipeline_arguments["output_resolution"] = 768
    if condition_images:
        pipeline_arguments["image"] = condition_images
    negative_prompt = request.get("negativePrompt")
    if negative_prompt and not args.official_turbo and not args.viggle_turbo and not args.consistency_lora and not args.viewpoint_orbit:
        pipeline_arguments["negative_prompt"] = negative_prompt
        pipeline_arguments["true_cfg_scale"] = 4.0

    image = pipe(**pipeline_arguments).images[0]
    if args.viewpoint_orbit and image.mode != "RGBA":
        raise RuntimeError("Viewpoint Orbit n’a pas renvoyé d’image RGBA ; vérifiez le runtime Qwen 2.1.")

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
