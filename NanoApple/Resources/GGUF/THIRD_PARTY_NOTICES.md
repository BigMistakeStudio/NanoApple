# Moteur GGUF embarqué

NanoApple inclut `sd-cli` de [leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp),
révision `09633572149742445487cdbc25431a1b92bd76ce` (6 octobre 2026), avec ggml
`89c4413f5da6fb20cc796f16033d37f129be81fd`.

Ce moteur inclut le correctif des listes de sigmas requis par Turbo.
Binaire Release Apple Silicon, Metal et shaders embarqués, cible macOS 14.
SHA-256 : `1a8602f2386ab1de4932de027222b05a5a8ae247c319372a61445050a45c9082`.

Construction : CMake 4.4.4, `SD_METAL=ON`, `SD_BUILD_SHARED_LIBS=OFF`,
`SD_BUILD_SHARED_GGML_LIB=OFF`, `SD_WEBP=OFF`, `SD_WEBM=OFF`,
`GGML_NATIVE=OFF`, `GGML_METAL_EMBED_LIBRARY=ON`,
`CMAKE_OSX_DEPLOYMENT_TARGET=14.0`, `CMAKE_OSX_ARCHITECTURES=arm64`.
Licences jointes dans ce dossier.
