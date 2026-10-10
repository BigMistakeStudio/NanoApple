#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
# SPDX-License-Identifier: GPL-3.0-only

"""Classify a locally generated image without contacting an external service."""

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    import torch
    from PIL import Image
    from transformers import AutoImageProcessor, AutoModelForImageClassification

    torch.set_num_threads(min(4, torch.get_num_threads()))
    processor = AutoImageProcessor.from_pretrained(args.model, local_files_only=True)
    model = AutoModelForImageClassification.from_pretrained(
        args.model, local_files_only=True, use_safetensors=True
    ).eval()
    with Image.open(args.image) as image:
        inputs = processor(images=image.convert("RGB"), return_tensors="pt")
    with torch.inference_mode():
        probabilities = torch.softmax(model(**inputs).logits, dim=-1)[0]

    label_to_id = {
        label.lower(): int(index)
        for label, index in model.config.label2id.items()
    }
    nsfw_index = label_to_id.get("nsfw")
    if nsfw_index is None or not 0 <= nsfw_index < probabilities.numel():
        raise ValueError("Le modèle local n’a pas de classe NSFW.")
    score = float(probabilities[nsfw_index].item())
    Path(args.output).write_text(
        json.dumps({"nsfwProbability": score}), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
