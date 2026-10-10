# SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
# SPDX-License-Identifier: GPL-3.0-only

"""Turbo runner contract checks without model downloads or a GPU."""
import json
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from PIL import Image
from test_viewpoint_orbit import runtime, Component


class TurboPipeline:
    def __init__(self, schedule):
        self.config = SimpleNamespace(sample_sigmas=schedule)
        self.transformer, self.vae, self.text_encoder = Component(), Component(), Component()
        self._get_qwen_prompt_embeds = lambda *a: None
        self.calls = []

    def enable_attention_slicing(self):
        pass

    def __call__(self, **kwargs):
        self.calls.append(kwargs)
        for i in range(8):
            kwargs['callback_on_step_end'](self, i, None, {})
        return SimpleNamespace(images=[Image.new('RGBA', (kwargs['width'], kwargs['height']), (1, 2, 3, 128))])


class TurboChecks(unittest.TestCase):
    def run_model(self, mode='create', schedule=None, flags=(), request_flags=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'reference.png'
            Image.new('RGB', (256, 256), 'red').save(source)
            request = dict(mode=mode, backend='diffusersTurbo', prompt='a boat',
                           negativePrompt='ignored', steps=30, seed=42, randomizeSeed=False,
                           resolution='custom', customWidth=256, customHeight=256,
                           referenceImages=[source.as_uri()] if mode == 'edit' else [])
            request.update(request_flags or {})
            manifest = root / 'request.json'
            manifest.write_text(json.dumps(request))
            pipe = TurboPipeline(schedule)
            torch = SimpleNamespace(float16='float16', bfloat16='bfloat16',
                backends=SimpleNamespace(mps=SimpleNamespace(is_available=lambda: True)),
                Generator=lambda **k: SimpleNamespace(manual_seed=lambda seed: seed))
            modules = {'torch': torch, 'diffusers': SimpleNamespace(
                FlowMatchEulerDiscreteScheduler=None,
                QwenImage21Pipeline=SimpleNamespace(from_pretrained=lambda *a, **k: pipe))}
            argv = ['qwen_runtime', '--model', str(root), '--request', str(manifest),
                    '--output', str(root/'output.png'), '--status', str(root/'status.json'),
                    '--official-turbo', *flags]
            with patch.dict(sys.modules, modules), patch.object(sys, 'argv', argv):
                runtime.main()
            self.assertTrue((root/'output.png').is_file())
            self.assertEqual(json.loads((root/'status.json').read_text())['progress'], 1.0)
            return pipe.calls[0]

    def test_creation_editing_transparency_use_saved_schedule_and_cfg_one(self):
        for mode in ['create', 'edit', 'transparentAsset']:
            with self.subTest(mode=mode):
                call = self.run_model(mode, [1.0, .97, .95, .92, .89, .84, .70, .41])
                self.assertEqual(call['num_inference_steps'], 8)
                self.assertEqual(call['true_cfg_scale'], 1.0)
                self.assertTrue(call['use_kv_cache'])
                self.assertNotIn('sigmas', call)
                self.assertNotIn('negative_prompt', call)
                self.assertEqual('image' in call, mode == 'edit')
                if mode == 'transparentAsset':
                    self.assertIn('RGBA', call['prompt'])

    def test_missing_or_wrong_checkpoint_schedule_fails(self):
        for schedule in [None, [], [1.0]*6]:
            with self.subTest(schedule=schedule), self.assertRaisesRegex(RuntimeError, 'calendrier officiel'):
                self.run_model(schedule=schedule)

    def test_adapters_and_alternative_encoder_are_rejected(self):
        for flag in ['--viggle-turbo', '--consistency-lora', '--text-encoder']:
            with self.subTest(flag=flag), self.assertRaisesRegex(ValueError, 'ne se combine pas'):
                self.run_model(flags=[flag, 'adapter'])
        for flag in ['useViggleTurbo', 'useConsistencyLoRA']:
            with self.subTest(flag=flag), self.assertRaises(ValueError):
                self.run_model(request_flags={flag: True})


if __name__ == '__main__':
    unittest.main()
