# SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
# SPDX-License-Identifier: GPL-3.0-only

"""CPU checks for Orbit's request contract, RGBA input and complete adapter loading.

Run with a Python that has Pillow. No model download or GPU is needed.
Optionally pass the JSON emitted by ViewpointOrbitChecks.swift to check the
Swift/Python wire contract for all 23 supported camera instructions.
"""

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "qwen_runtime", ROOT / "NanoApple/Resources/Runtime/qwen_runtime.py"
)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
CONTRACT = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else None


def request():
    return dict(
        mode="viewpointOrbit", backend="diffusers", prompt="stale user prompt",
        viewpointOrbit=dict(rotation="right90", elevation="eyeLevel"),
        referenceImages=["source.png"], resolution="custom", customWidth=768,
        customHeight=768, steps=40, seed=42, randomizeSeed=False,
        enhancePrompt=False, negativePrompt="must be ignored",
    )


def args(**changes):
    values = dict(viewpoint_orbit="orbit.safetensors", viggle_turbo=None,
                  consistency_lora=None, text_encoder=None)
    return SimpleNamespace(**(values | changes))


class Tensor:
    def __init__(self, shape):
        self.shape = shape

    def to(self, **kwargs):
        return self


class Component:
    def to(self, device):
        return self


class Pipeline:
    def __init__(self):
        self.transformer = Component()
        self.transformer.dtype = "float16"
        linear = SimpleNamespace(in_features=4, out_features=4)
        mlp = SimpleNamespace(in_features=4, out_features=7)
        out = SimpleNamespace(in_features=7, out_features=4)
        block = SimpleNamespace(
            attn=SimpleNamespace(to_q=linear, to_k=linear, to_v=linear, to_out=[linear]),
            img_mlp=SimpleNamespace(gate_layer=mlp, proj=mlp, out=out),
        )
        self.transformer.transformer_blocks = [block] * 32
        self.vae, self.text_encoder = Component(), Component()
        self._get_qwen_prompt_embeds = lambda *a: None
        self.loaded = None
        self.call = None
        self.rgb_output = False

    def load_lora_weights(self, weights, **kwargs):
        self.loaded = (weights, kwargs)

    def enable_attention_slicing(self):
        pass

    def __call__(self, **kwargs):
        self.call = kwargs
        kwargs["callback_on_step_end"](self, 39, None, {})
        image = kwargs["image"][0].copy()
        if self.rgb_output:
            image = image.convert("RGB")
        return SimpleNamespace(images=[image])


def weights():
    result = {}
    for index in range(32):
        for name, dims in {
            "attn.to_q": (4, 4), "attn.to_k": (4, 4), "attn.to_v": (4, 4),
            "attn.to_out.0": (4, 4), "img_mlp.gate_layer": (4, 7),
            "img_mlp.proj": (4, 7), "img_mlp.out": (7, 4),
        }.items():
            prefix = f"diffusion_model.transformer_blocks.{index}.{name}"
            result[f"{prefix}.lora_A.weight"] = Tensor((32, dims[0]))
            result[f"{prefix}.lora_B.weight"] = Tensor((dims[1], 32))
    return result


def tensor_modules(data):
    return {"safetensors.torch": SimpleNamespace(load_file=lambda *a, **k: data)}


class OrbitChecks(unittest.TestCase):
    def test_swift_wire_contract_and_23_instructions(self):
        if CONTRACT is None:
            self.skipTest("Pass the Swift contract JSON for cross-language checks")
        data = json.loads(CONTRACT.read_text())
        self.assertEqual(len(data), 23)
        for case in data:
            runtime.validate_orbit_request(case, args())
            self.assertEqual(runtime.orbit_prompt(case), case["prompt"])

    def test_rejects_invalid_combinations_before_model_loading(self):
        for changes in (
            dict(referenceImages=[]), dict(referenceImages=["a", "b"]),
            dict(backend="ggufQ6"), dict(backend="diffusersHeretic"),
            dict(enhancePrompt=True), dict(enhancedPrompt="rewrite"),
            dict(maskImage="mask.png"), dict(steps=6), dict(customWidth=1024),
            dict(useViggleTurbo=True), dict(useConsistencyLoRA=True),
            dict(viewpointOrbit=dict(rotation="keepAngle", elevation="eyeLevel")),
            dict(viewpointOrbit=dict(rotation="right360", elevation="eyeLevel")),
        ):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                runtime.validate_orbit_request(request() | changes, args())
        for overrides in (dict(viewpoint_orbit=None), dict(viggle_turbo="turbo"),
                          dict(consistency_lora="consistency"), dict(text_encoder="heretic")):
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                runtime.validate_orbit_request(request(), args(**overrides))
        runtime.validate_orbit_request(dict(mode="edit"), args(viewpoint_orbit=None))

    def test_rgba_padding_keeps_geometry_and_partial_alpha(self):
        with tempfile.TemporaryDirectory(prefix="orbit reference ") as directory:
            source = Path(directory) / "subject image.png"
            Image.new("RGBA", (384, 768), (90, 120, 150, 128)).save(source)
            image = runtime.load_orbit_reference(source.as_uri())
            self.assertEqual(image.mode, "RGBA")
            self.assertEqual(image.size, (768, 768))
            self.assertEqual(image.getpixel((0, 384))[3], 0)
            self.assertEqual(image.getpixel((192, 384)), (90, 120, 150, 128))
            self.assertEqual(image.getpixel((575, 384))[3], 128)
            self.assertEqual(image.getpixel((576, 384))[3], 0)

    def test_rejects_opaque_and_empty_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.png"
            for mode, color in (("RGB", (255, 0, 0)), ("RGBA", (255, 0, 0, 255)),
                                ("RGBA", (0, 0, 0, 0))):
                with self.subTest(mode=mode, color=color):
                    Image.new(mode, (24, 24), color).save(source)
                    with self.assertRaisesRegex(ValueError, "transparent"):
                        runtime.load_orbit_reference(str(source))

    def test_opaque_reference_fails_before_importing_gpu_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, adapter, manifest = root / "source.png", root / "orbit", root / "request.json"
            Image.new("RGB", (24, 24), (255, 0, 0)).save(source)
            adapter.touch()
            manifest.write_text(json.dumps(request() | dict(referenceImages=[str(source)])))
            argv = ["qwen_runtime", "--model", str(root), "--request", str(manifest),
                    "--output", str(root / "output.png"), "--status", str(root / "status.json"),
                    "--viewpoint-orbit", str(adapter)]
            with patch.dict(sys.modules, {"torch": None, "diffusers": None}), patch.object(sys, "argv", argv):
                with self.assertRaisesRegex(ValueError, "transparent"):
                    runtime.main()

    def test_palette_transparency_is_kept(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "palette.png"
            image = Image.new("P", (16, 16), 0)
            image.putpalette([0, 0, 0, 255, 0, 0] + [0] * 762)
            image.paste(1, (4, 4, 12, 12))
            image.save(source, transparency=0)
            self.assertEqual(runtime.load_orbit_reference(str(source)).getchannel("A").getextrema(), (0, 255))

    def test_loads_all_448_split_weights_and_refuses_partial_adapters(self):
        data, pipe = weights(), Pipeline()
        with patch.dict(sys.modules, tensor_modules(data)):
            runtime.load_viewpoint_orbit_lora(pipe, "orbit")
        loaded, options = pipe.loaded
        self.assertEqual(len(loaded), 448)
        self.assertEqual(options["adapter_name"], "viewpoint_orbit")
        self.assertTrue(all(key.startswith("transformer.") for key in loaded))
        for broken in (dict(list(data.items())[1:]), data | {"unexpected": Tensor((1,))},
                       data | {next(iter(data)): Tensor((16, 4))}):
            with self.subTest(), patch.dict(sys.modules, tensor_modules(broken)), self.assertRaises(ValueError):
                runtime.load_viewpoint_orbit_lora(Pipeline(), "orbit")

    def test_runner_uses_canonical_prompt_cfg_and_rgba_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, adapter = root / "source.png", root / "orbit.safetensors"
            output, status, manifest = root / "result.png", root / "status.json", root / "request.json"
            Image.new("RGBA", (384, 768), (90, 120, 150, 128)).save(source)
            adapter.touch()
            manifest.write_text(json.dumps(request() | dict(referenceImages=[source.as_uri()])))
            pipe = Pipeline()
            torch = SimpleNamespace(
                float16="float16", bfloat16="bfloat16",
                backends=SimpleNamespace(mps=SimpleNamespace(is_available=lambda: True)),
                Generator=lambda **k: SimpleNamespace(manual_seed=lambda seed: seed),
            )
            modules = tensor_modules(weights()) | {
                "torch": torch,
                "diffusers": SimpleNamespace(
                    FlowMatchEulerDiscreteScheduler=None,
                    QwenImage21Pipeline=SimpleNamespace(from_pretrained=lambda *a, **k: pipe)),
            }
            argv = ["qwen_runtime", "--model", str(root), "--request", str(manifest),
                    "--output", str(output), "--status", str(status), "--viewpoint-orbit", str(adapter)]
            with patch.dict(sys.modules, modules), patch.object(sys, "argv", argv):
                runtime.main()
                self.assertEqual(pipe.call["true_cfg_scale"], 1.0)
                self.assertEqual(pipe.call["num_inference_steps"], 40)
                self.assertEqual(pipe.call["output_resolution"], 768)
                self.assertEqual(pipe.call["prompt"], runtime.orbit_prompt(request()))
                self.assertNotIn("negative_prompt", pipe.call)
                self.assertNotIn("sigmas", pipe.call)
                with Image.open(output) as result:
                    self.assertEqual(result.mode, "RGBA")
                    self.assertEqual(result.size, (768, 768))
                    self.assertEqual(result.getchannel("A").getextrema(), (0, 128))
                self.assertEqual(json.loads(status.read_text())["progress"], 1.0)
                pipe.rgb_output = True
                with self.assertRaisesRegex(RuntimeError, "RGBA"):
                    runtime.main()


if __name__ == "__main__":
    unittest.main()
