# NanoApple

Application macOS native et locale pour Qwen-Image 2.1, conçue pour rester simple en usage courant tout en exposant des réglages avancés.

## Licence et usages autorisés / License and permitted use

Le code original de NanoApple, ses scripts, sa documentation associée et ses ressources originales sont publiés sous **[GNU GPLv3](LICENSE)** (`GPL-3.0-only`), avec conservation des mentions de copyright de **Frédéric Genevey / BigMistakeStudio**. La réutilisation commerciale est autorisée. La redistribution de l’application, modifiée ou non, implique de fournir aux destinataires le code source correspondant sous GPLv3. Consultez la [notice du projet](NOTICE).

**Les modèles Qwen Image 2.1, Turbo, leurs quantifications et les adaptateurs conservent leur licence Qwen Research : recherche ou évaluation non commerciales uniquement, sauf licence distincte de Qwen.** La licence Apache d’un encodeur ne change pas cette restriction. Les composants tiers conservent leurs licences propres. Aucun poids de modèle n’est fourni dans ce dépôt. Les [notices et textes des licences](THIRD_PARTY_NOTICES.md) sont intégrés à l’application et accessibles depuis Réglages.

Original NanoApple code, scripts, accompanying documentation and original project assets are licensed under **GNU GPL version 3 only**. Commercial reuse is allowed; redistributing the application, including modified versions, requires providing the corresponding source under GPLv3 and retaining copyright notices. Independent third-party components retain their own licenses. **Qwen image models and derivatives remain restricted to non-commercial research or evaluation unless separately licensed by Qwen.** The application supports French and English through macOS app language settings. See [third-party notices](THIRD_PARTY_NOTICES.md) for original agreements and corresponding source for bundled MPL components.

## Base actuelle

- code applicatif SwiftUI autonome ; composants tiers détaillés dans les notices de licence ;
- interface SwiftUI pour Apple Silicon et macOS 14 ou version ultérieure ;
- interface en français et en anglais, sélectionnée automatiquement selon la
  langue de l’application dans macOS ; les conseils pour le Mac, les modèles,
  le guide d’installation et les erreurs disposent aussi de traductions ;
- studio simplifié par défaut avec prompt, choix du modèle, préréglages, format
  et taille de l’image ; le bouton
  « Expert » retrouve tous les réglages du studio et le choix d'interface est
  conservé au prochain démarrage ;
- assistant de premier lancement pour choisir le stockage, installer le runtime et
  Qwen-Image 2.1, puis proposer Viggle Turbo en option ; le guide reste accessible
  depuis Modèles ;
- modes création, modification, fiche personnage et PNG transparent ;
- préréglages et panneau avancé ;
- formats 1:1, 16:9, 9:16, 4:5, ultralarge et 2K, plus dimensions
  personnalisées de 256 à 2048 px par multiples de 32 ;
- bibliothèque de personnages et de créations ;
- accès persistant à un SSD externe par bookmark sécurisé macOS ;
- installateur natif des dépôts officiels Qwen-Image 2.1 et des deux Prompt Enhancers ;
- si « Améliorer le prompt » est activé avec Diffusers/MPS, NanoApple réécrit
  l’instruction avec le modèle local adapté à la présence de références,
  permet de préparer et corriger le prompt avant la génération, puis de choisir
  entre l’original et la version améliorée ; l’original reste conservé dans la variante ;
- après génération, le prompt amélioré peut être envoyé dans l’instruction principale
  pour une nouvelle retouche ; l’onglet Prompts garde un historique des prompts
  utilisés, réutilisable et effaçable sans supprimer les créations ;
- durée estimée à partir des générations comparables déjà enregistrées, puis temps
  restant actualisé pendant la génération ; un brouillon rapide peut être repris
  avec 40 étapes pour préparer sa version finale ;
- reprise des fichiers partiels, progression détaillée et contrôle SHA-256 des poids ;
- trois variantes Turbo dans le Studio, les Réglages, les Modèles et le guide
  d’installation : [officielle complète](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo)
  (32,5 Go) ; [GGUF Q8 et AtomicChat AD-Q5](https://huggingface.co/AtomicChat/Qwen-Image-2.1-Turbo-GGUF)
  (générateurs de 7,6 et 5,4 Go ; paquets complets de 17,7 et 11,9 Go) ;
- détection Apple Silicon, Metal, macOS, puce et mémoire ; pastilles Recommandé,
  Sous réserve et Ne fonctionnera pas, accompagnées de raisons. Les conseils
  initiaux à ~1024 px visent 64 Go pour le complet, 32 Go avec une puce Pro/Max/Ultra
  pour Q8 et 24 Go pour AtomicChat Q5. Une grande image demande davantage de marge.
  Ces seuils sont des conseils prudents, pas des mesures de vitesse. La RAM faible
  reste « Sous réserve » ; seuls Intel, Metal absent ou macOS <14 sont incompatibles.
  Un nouveau profil choisit le Turbo conseillé ; les choix enregistrés restent conservés ;
- Turbo utilise le calendrier officiel de 8 étapes, CFG 1 et le cache KV,
  sans prompt négatif ni LoRA Viggle, Consistency ou Orbit. Les anciens choix
  GGUF enregistrés sont repris avec Turbo ; les anciens poids ne sont pas supprimés.
  Installez le runtime et le paquet choisi depuis Modèles. Le bouton d’installation
  groupée suit le choix et ajoute le filtre NSFW s’il est activé ; il ne télécharge
  ni les autres variantes ni les Prompt Enhancers facultatifs ;
- adaptateur facultatif Viggle Turbo pour le moteur Diffusers/MPS : choix dans le
  Studio, 6 étapes fixes, jusqu’à 3 références, sans prompt négatif ; les poids
  s’installent séparément depuis la page Modèles ;
- adaptateur facultatif [Consistency LoRA](https://huggingface.co/ausboss/Qwen-Image-2.1-Consistency-LoRA)
  pour les retouches avec une seule image de référence et le modèle Diffusers/MPS
  complet : l’option « Préserver le cadrage » se trouve en mode Expert et le
  checkpoint recommandé de l’étape 1500 s’installe depuis Modèles. Il est
  désactivé par défaut et ne se combine pas avec Viggle Turbo. L’auteur signale
  qu’il peut freiner les changements de pose ; ses essais couvrent surtout des
  images proches de 1 Mpx, pas le 2K. Le Studio signale les écarts de taille
  avec la référence et peut reprendre exactement ses dimensions si elles sont
  prises en charge. Cette option utilise CFG 1 et ignore le prompt négatif.
  Les poids ComfyUI sont convertis au chargement pour le transformeur Diffusers ;
- mode **Angle de vue** avec [Viewpoint Orbit](https://huggingface.co/ML-Intern-lab/Qwen-Image-2.1-viewpoint-orbit-LoRA),
  accessible dans le Studio Expert avec Qwen complet : installer le paquet
  facultatif d’environ 168 Mo depuis Modèles, ajouter une seule référence avec
  transparence réelle, puis choisir la rotation relative et la hauteur de caméra.
  Chaque génération part de cette référence, ajustée sans déformation et centrée
  dans un carré transparent de 768 × 768 px ; la sortie est un PNG RGBA.
  Les 40 étapes sont fixes, l’instruction est préparée automatiquement et les
  autres adaptateurs, masques et améliorations de prompt sont désactivés pour
  cette opération. Les angles sont conservés avec le projet et ses variantes.
  Les 448 tenseurs du checkpoint `gate_up_split` sont vérifiés au chargement.
  Les faces cachées et les détails peuvent être réinventés ; les résultats sur
  MPS restent à évaluer visuellement. Cette fonction utilise la licence Qwen Research ;
- filtre NSFW local activé par défaut : le classifieur
  [Falconsai/nsfw_image_detection](https://huggingface.co/Falconsai/nsfw_image_detection)
  s’installe depuis Modèles (environ 343 Mo). Les nouvelles images signalées sont
  masquées dans l’aperçu, la bibliothèque et le comparateur, avec un bouton pour
  les afficher. Si l’analyse échoue, l’image reste masquée jusqu’à cette action.
  Une génération demande le classifieur tant que le filtre est actif ; il se
  désactive dans Réglages. Les fichiers ne sont jamais supprimés ;
  les créations antérieures à son installation ne sont pas analysées. Le modèle
  classe uniquement « normal » et « NSFW » et peut se tromper ;
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

- Mac Apple Silicon et macOS 14 ou ultérieur ; prévoir au moins 40 Go libres
  pour les poids complets ou Turbo et le runtime, plus les créations ;
- 64 Go de mémoire unifiée conseillés pour le complet, 32 Go pour GGUF Q8,
  24 Go pour AtomicChat Q5 ; les deux GGUF utilisent un moteur C++/Metal embarqué,
  avec le calendrier Turbo exact et CFG 1. La variante Q8 inclut un encodeur Q8 ;
  la variante compacte inclut un encodeur Q4, qui peut modifier davantage les images.
  La qualité et la vitesse sur chaque Mac restent à mesurer ;
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

Les contrôles Orbit peuvent être exécutés sans GPU ni téléchargement de modèles :

```bash
swiftc -swift-version 6 NanoApple/Domain/*.swift Scripts/ViewpointOrbitChecks.swift \
  -o /tmp/nanoapple-orbit-checks
/tmp/nanoapple-orbit-checks > /tmp/nanoapple-orbit-contract.json
python3 Scripts/test_viewpoint_orbit.py /tmp/nanoapple-orbit-contract.json
```

Le Python des contrôles doit disposer de Pillow. Ils vérifient la compatibilité
des anciens projets, les 23 instructions échangées entre Swift et Python,
la conservation de l’alpha, le chargement complet des poids et le chemin du
runner avec un pipeline simulé. Ils ne mesurent pas la qualité du modèle sur Mac.

Les contrôles Turbo (moteur simulé, sans téléchargement ni GPU) :

```bash
swiftc -swift-version 6 NanoApple/Domain/*.swift Scripts/TurboBackendChecks.swift -o /tmp/nanoapple-turbo-checks
/tmp/nanoapple-turbo-checks
python3 Scripts/test_official_turbo.py
swiftc -swift-version 6 NanoApple/Domain/*.swift Scripts/MacModelAdviceChecks.swift -o /tmp/nanoapple-advice-checks
/tmp/nanoapple-advice-checks
```

Le catalogue de traductions est vérifié sans dépendance Python supplémentaire :

```bash
python3 Scripts/test_localization.py
```

Ce contrôle vérifie la couverture anglaise du catalogue, les paramètres des
messages formatés et les clés de traduction utilisées dans le code Swift.
