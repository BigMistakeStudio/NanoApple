#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
# SPDX-License-Identifier: GPL-3.0-only

"""Rewrite a NanoApple request with the locally installed Qwen PE model."""

import argparse
import json
from pathlib import Path
from urllib.parse import unquote, urlparse


def local_path(value):
    parsed = urlparse(value)
    return Path(unquote(parsed.path) if parsed.scheme == "file" else value)


def rewritten_prompt(text):
    # Qwen PE emits its answer as JSON after an optional thinking block.
    answer = text.rpartition("</think>")[2] if "</think>" in text else text
    result = json.loads(answer.strip())
    prompt = result.get("rewritten_prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("L’améliorateur n’a pas renvoyé de prompt valide.")
    return prompt.strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--request", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--device", choices=("cpu", "mps"), default="mps")
    parser.add_argument("--max-new-tokens", type=int, default=1024)
    args = parser.parse_args()

    import torch
    from transformers import (
        AutoModelForCausalLM,
        AutoModelForImageTextToText,
        AutoProcessor,
        AutoTokenizer,
        StoppingCriteria,
        StoppingCriteriaList,
    )

    class StopAfterJSON(StoppingCriteria):
        def __init__(self, tokenizer, prompt_length):
            self.tokenizer = tokenizer
            self.prompt_length = prompt_length

        def __call__(self, input_ids, scores, **kwargs):
            generated = self.tokenizer.decode(
                input_ids[0, self.prompt_length:], skip_special_tokens=True
            )
            try:
                rewritten_prompt(generated)
                return True
            except ValueError:
                return False

    request = json.loads(Path(args.request).read_text(encoding="utf-8"))
    if args.device == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("Le GPU Metal (MPS) n’est pas disponible pour l’améliorateur de prompt.")
    dtype = torch.float16 if args.device == "mps" else torch.bfloat16
    references = request.get("referenceImages") or []
    model_dir = Path(args.model) / ("image-to-image" if references else "text-to-image")
    system_prompt = (model_dir / "system_prompt.txt").read_text(encoding="utf-8").strip()
    user_prompt = request["prompt"]

    if references:
        from PIL import Image

        processor = AutoProcessor.from_pretrained(model_dir, local_files_only=True)
        model = AutoModelForImageTextToText.from_pretrained(
            model_dir, dtype=dtype, local_files_only=True, low_cpu_mem_usage=True
        ).eval().to(args.device)
        content = []
        for reference in references:
            with Image.open(local_path(reference)) as image:
                content.append({"type": "image", "image": image.convert("RGB")})
        content.append({"type": "text", "text": user_prompt})
        messages = [
            {"role": "system", "content": [{"type": "text", "text": system_prompt}]},
            {"role": "user", "content": content},
        ]
        inputs = processor.apply_chat_template(
            messages, add_generation_prompt=True, tokenize=True,
            return_dict=True, return_tensors="pt", enable_thinking=False,
        ).to(model.device)
        tokenizer = processor.tokenizer
    else:
        tokenizer = AutoTokenizer.from_pretrained(model_dir, local_files_only=True)
        model = AutoModelForCausalLM.from_pretrained(
            model_dir, dtype=dtype, local_files_only=True, low_cpu_mem_usage=True
        ).eval().to(args.device)
        text = tokenizer.apply_chat_template(
            [{"role": "system", "content": system_prompt},
             {"role": "user", "content": user_prompt}],
            tokenize=False, add_generation_prompt=True, enable_thinking=False,
        )
        inputs = tokenizer(text, return_tensors="pt").to(model.device)

    with torch.inference_mode():
        output = model.generate(
            **inputs, max_new_tokens=args.max_new_tokens,
            do_sample=True, temperature=1.0, top_p=0.95, top_k=20,
            stopping_criteria=StoppingCriteriaList([
                StopAfterJSON(tokenizer, inputs["input_ids"].shape[1])
            ]),
        )
    generated = tokenizer.decode(
        output[0, inputs["input_ids"].shape[1]:], skip_special_tokens=True
    )
    Path(args.output).write_text(
        json.dumps({"enhancedPrompt": rewritten_prompt(generated)}, ensure_ascii=False),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
