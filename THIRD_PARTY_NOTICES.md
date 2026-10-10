# Third-party notices / Notices des composants tiers

Original NanoApple code is licensed under GNU GPLv3 (GPL-3.0-only). Independently licensed third-party components are excluded from that grant and keep the licenses below. Keep these notices and the original agreements in `NanoApple/Resources/Legal/` with redistributed copies. Xcode includes that folder in the macOS application.

La licence du code NanoApple ne remplace pas celles des composants tiers. Conservez leurs licences et attributions avec chaque copie redistribuée. Elles accompagnent aussi l'application macOS.

## Bundled software / Logiciels intégrés

| Component | Version / revision | Terms and bundled notices |
| --- | --- | --- |
| stable-diffusion.cpp / sd-cli | `09633572149742445487cdbc25431a1b92bd76ce` | MIT. `Legal/sd-cli/` includes oniguruma (BSD), utf8proc (MIT and Unicode data), darts-clone (BSD), nlohmann JSON, zip, miniz, stb, and YaRN notices. |
| ggml | `89c4413f5da6fb20cc796f16033d37f129be81fd` | MIT, with original component copyrights. |
| uv | 0.10.9 (`f675560f3`, 2026-03-06) | MIT OR Apache-2.0. `Legal/uv/` includes a conservative inventory of its locked Cargo dependency graph for Apple Silicon. |
| Rust standard library linked into uv | 1.93.1 (`01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf`, identified in the binary) | MIT OR Apache-2.0 and component notices in `Legal/uv/Rust-1.93.1/`. The upstream inventory also covers other platforms; it is retained conservatively. |
| CPython / python-build-standalone | 3.12.11, Astral release 20250818, Apple Silicon pgo+lto | PSF/CNRI and original dependency licenses in `Legal/Python/`. Both embedded Mach-O payloads have identical code/data sections to that release; relocation and signing change their whole-file hashes. |
| pip | 24.3.1 | MIT and vendored dependency licenses in `Legal/Python/pip/`. |

The current sd-cli includes CPU and Metal support. WebP, WebM, KleidiAI and llamafile were disabled. Llamafile's notice is also retained for older binaries in repository history. No model weights are distributed in this repository.

### MPL corresponding source

Unchanged source archives for uv's `astral-pubgrub`, `astral-version-ranges`, `option-ext`, and `priority-queue` are supplied in `Legal/Sources/`. MPL-2.0 is selected for priority-queue's LGPL/MPL choice; MIT is selected for configparser's MIT/LGPL choice. The unchanged source for pip's vendored certifi is also supplied. These components retain their original licenses and are excluded from NanoApple's own-code license. `Legal/uv/dependencies.json` links to each recorded crate version and its declared terms. The inventory includes the non-dev Cargo dependency closure; optional features and build-time selection can remove some entries.

## Downloaded models / Modèles téléchargés

**Qwen Research permits non-commercial research or evaluation only. Commercial use requires a separate Qwen license:** `model-business@notice.qwencloud.com`. Quantization and an Apache-licensed encoder do not remove the image generator's restriction. Downloading or using Qwen materials constitutes acceptance under its agreement.

**Qwen Research autorise uniquement la recherche ou l'évaluation non commerciales. Un usage commercial nécessite une licence distincte de Qwen.** La quantification ou la licence Apache d'un encodeur ne change pas cette restriction. Selon cet accord, télécharger ou utiliser les modèles vaut acceptation.

NanoApple displays these terms before download and writes copies of the agreements and notices into the package's `Legal` directory before downloading weights. Selected upstream README, LICENSE and NOTICE files are also retained. The installed `manifest.json` records exact repository revisions, file sizes and supplied SHA-256 hashes. The application's legal documents have their own SHA-256 inventory in `Legal/inventory.json`.

Required Qwen notice:

> Qwen is licensed under the Qwen RESEARCH LICENSE AGREEMENT, Copyright (c) 2026 Hangzhou Tongyi Laboratory Technology Co., Ltd. All Rights Reserved.

Original agreements are in `Legal/Models/`. AtomicChat links to Qwen's Turbo agreement; Comfy-Org links to the base model agreement. Viewpoint Orbit's LICENSE contains Qwen Research terms even though its Hub metadata has no license field. Heretic's original Apache notice and Viggle's original notice are supplied in `Legal/Models/Upstream/`.

## Runtime packages installed on demand

PyTorch and torchvision (BSD), Diffusers (Apache-2.0, revision `1d5d056ecff3a8c1d887a7dd1aa66ca4a0323458`), Transformers, Accelerate, PEFT, Safetensors and SentencePiece (Apache-2.0), Pillow (HPND), and their dependencies are installed by uv directly from their upstream distributions. They are not distributed in this Git repository. uv retains the distribution metadata and supplied licenses in the selected runtime directory. Redistributing an installed runtime requires keeping those notices and checking the versions actually installed; several runtime requirements remain unpinned.

## Audit sources

Audit date: 2026-10-10. Primary sources: the model repositories below and their original licenses; [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp), [uv 0.10.9](https://github.com/astral-sh/uv/tree/0.10.9), [Python standalone release 20250818](https://github.com/astral-sh/python-build-standalone/releases/tag/20250818), [pip 24.3.1](https://pypi.org/project/pip/24.3.1/), and [Rust 1.93.1](https://github.com/rust-lang/rust/tree/1.93.1).

### Model license snapshots

| Repository | Terms | Audited revision |
| --- | --- | --- |
| [AtomicChat/Qwen-Image-2.1-Turbo-GGUF](https://huggingface.co/AtomicChat/Qwen-Image-2.1-Turbo-GGUF) | Qwen Research (research/evaluation only) | `bb25d06bc74119c12207243d68917951e6d9c232` |
| [Comfy-Org/Qwen-Image-2.1](https://huggingface.co/Comfy-Org/Qwen-Image-2.1) | Qwen Research (research/evaluation only) | `df94239739eef7205973a145ffa6f441f7b64e84` |
| [Falconsai/nsfw_image_detection](https://huggingface.co/Falconsai/nsfw_image_detection) | Apache-2.0 | `96cb0d0342c7afb80cab76ecc58b265fa44da256` |
| [ML-Intern-lab/Qwen-Image-2.1-viewpoint-orbit-LoRA](https://huggingface.co/ML-Intern-lab/Qwen-Image-2.1-viewpoint-orbit-LoRA) | Qwen Research (research/evaluation only) | `b5283f45e9291147ea428c5360445d6cee4d9d63` |
| [Qwen/Qwen-Image-2.1-PE-I2I](https://huggingface.co/Qwen/Qwen-Image-2.1-PE-I2I) | Qwen Research (research/evaluation only) | `72927bc08afc99b7888ceb7d7d51a12db3700bbd` |
| [Qwen/Qwen-Image-2.1-PE-T2I](https://huggingface.co/Qwen/Qwen-Image-2.1-PE-T2I) | Qwen Research (research/evaluation only) | `f3ed7985c788ad75b3ab7223e0c4c51e2a43545b` |
| [Qwen/Qwen-Image-2.1-Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo) | Qwen Research (research/evaluation only) | `d65dbc9a7e8f6b5479e33dee6030eaab2a906509` |
| [Qwen/Qwen-Image-2.1](https://huggingface.co/Qwen/Qwen-Image-2.1) | Qwen Research (research/evaluation only) | `d26bb61231c349cf6b7896fa83353113880e1ba3` |
| [Qwen/Qwen3-VL-8B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF) | Apache-2.0 | `f982a07559d4a2f6c8744d840bf6fccab30eea96` |
| [Viggle/Qwen-Image-2.1-viggle-turbo](https://huggingface.co/Viggle/Qwen-Image-2.1-viggle-turbo) | Qwen Research (research/evaluation only) | `009a44a895ef85f7e643c80fdca9543795248867` |
| [ausboss/Qwen-Image-2.1-Consistency-LoRA](https://huggingface.co/ausboss/Qwen-Image-2.1-Consistency-LoRA) | Qwen Research (research/evaluation only) | `8f05b0fa027d517fa396fb31b71e0eaf48110e89` |
| [pottokao/Qwen-Image-2.1-Text-Encoder-Heretic](https://huggingface.co/pottokao/Qwen-Image-2.1-Text-Encoder-Heretic) | Apache-2.0 | `047e54342fc4bfcd2addd54049db9c90bb74731e` |
