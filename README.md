# NanoApple

Application macOS native et locale pour Qwen-Image 2.1, conçue pour rester simple en usage courant tout en exposant des réglages avancés.

## Base actuelle

- nouveau projet autonome, créé de zéro et sans dépendance externe au code source ;
- interface SwiftUI pour Apple Silicon et macOS 14 ou version ultérieure ;
- modes création, modification, fiche personnage et PNG transparent ;
- préréglages et panneau avancé ;
- formats 1:1, 16:9, 9:16, 4:5, ultralarge et 2K, plus dimensions
  personnalisées de 256 à 2048 px par multiples de 32 ;
- bibliothèque de personnages et de créations ;
- accès persistant à un SSD externe par bookmark sécurisé macOS ;
- installateur natif des dépôts officiels Qwen-Image 2.1 et des deux Prompt Enhancers ;
- si « Améliorer le prompt » est activé avec Diffusers/MPS, NanoApple réécrit
  l’instruction avec le modèle local adapté à la présence de références,
  affiche le prompt enrichi et conserve le texte saisi dans la variante ;
- reprise des fichiers partiels, progression détaillée et contrôle SHA-256 des poids ;
- deux moteurs locaux : Diffusers/MPS avec les poids complets, ou GGUF Q6 avec
  `stable-diffusion.cpp` et Metal ;
- installateur guidé du paquet GGUF Q6 (transformer, encodeur Qwen3-VL Q4,
  projecteur visuel Q8 et VAE BF16, environ 12,3 Go) ;
- adaptateur facultatif Viggle Turbo pour le moteur Diffusers/MPS : choix dans le
  Studio, 6 étapes fixes, jusqu’à 3 références, sans prompt négatif ; les poids
  s’installent séparément depuis la page Modèles ;
- catalogue de chaînes et accès centralisé `L10n`, prêts pour les traductions futures ;
- aucun téléchargement de modèle effectué sans action explicite de l’utilisateur.

## Guide de prompt et évaluation

Le studio propose un guide adapté au mode de création : une action par image,
une modification précise avec les éléments à préserver, le rôle numéroté des
références, le texte exact à afficher et le choix du format dans les paramètres.
Il montre l’instruction préparée avec le préréglage avant la génération. Le mode
Modification exige une image de référence.

Chaque variante peut recevoir une évaluation enregistrée dans son projet :
verdict, défauts observés, correction souhaitée et préférence esthétique séparée.
Le studio compare les dimensions demandées aux pixels obtenus et, pour un PNG
transparent, vérifie la présence de pixels effectivement transparents. La qualité
des contours et la fidélité au prompt restent à examiner visuellement.

Ces règles sont adaptées du projet [Qwen Image Gen de Craft Skills](https://github.com/ZSeven-W/craft-skills/tree/main/skills/qwen-image-gen),
publié sous licence Apache 2.0. Le guide fonctionne localement, sans modèle de
texte supplémentaire.

## Configuration matérielle

- minimum pratique pour le moteur GGUF Q6 : Mac Apple Silicon, macOS 14,
  24 Go de mémoire unifiée et environ 20 Go libres pour l’application, les
  poids et les créations ;
- configuration recommandée : 32 Go pour les formats jusqu’à 1344 px et
  64 Go pour le 2K ou le moteur Diffusers complet ;
- sous 32 Go, NanoApple active automatiquement le mémoire-mappage, la
  segmentation Metal, le streaming des couches et le décodage VAE par tuiles ;
- le 2K est fonctionnel mais très lent : sur un M2 Max 64 Go, un test
  2048 × 1152 d’une seule étape a demandé environ 5 min 36 s. Pour un MacBook
  Air 24 Go, les formats 1024 px sont donc conseillés.

## Construire

```bash
cd NanoApple
python3 Scripts/make_xcode_project.py
xcodebuild -project NanoApple.xcodeproj -scheme NanoApple \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Le moteur GGUF embarqué est compilé pour Apple Silicon et macOS 14 ou version
ultérieure. Ses informations de provenance et licences figurent dans
`NanoApple/Resources/GGUF/`.
