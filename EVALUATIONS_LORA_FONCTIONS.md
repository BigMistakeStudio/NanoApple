# LoRA et fonctions à évaluer pour NanoApple

Évaluation documentaire du 30 septembre 2026. Les résultats cités sont ceux des auteurs sur leur matériel ; aucune génération locale NanoApple n'a encore été exécutée pour ces pistes.

Mise à jour du 3 octobre 2026 : réexamen de Fix avec lecture directe du workflow et de l'en-tête des poids ; ajout de Viewpoint Orbit, Noct Q et du VAE HDR. Les textes des deux publications X ont été récupérés via le miroir public FxTwitter, puis leurs modèles ont été examinés sur Hugging Face. Les vidéos des publications n'ont pas été évaluées visuellement. Aucun modèle n'a été installé ni testé en inférence pendant cette analyse.

## 1. Doodle-in LoRA pour Qwen-Image 2.1

Source : [fiche du modèle](https://huggingface.co/ML-Intern-lab/Qwen-Image-2.1-doodle-in-LoRA) et [fichiers](https://huggingface.co/ML-Intern-lab/Qwen-Image-2.1-doodle-in-LoRA/tree/main).

**Fonction envisagée :** en mode Modification, dessiner un contour magenta sur une photo et nommer un objet à insérer à cet endroit. La fiche limite l'usage à un objet et un dessin par retouche. Elle indique des traits opaques RGB `(255, 0, 255)`, de 3 à 7 px selon la taille de l'image, et le préfixe de prompt `<doodle> Turn the magenta scribble into …`.

**État dans NanoApple :** le moteur Diffusers/MPS accepte déjà une image de référence, un prompt et les LoRA Viggle Turbo ou Consistency. Le masque actuel est appliqué *après* la génération avec `Image.composite` ; il ne constitue pas l'image annotée que ce LoRA reçoit en entrée. Il faudrait donc un dessin conservé comme couche distincte, puis une copie de la référence avec le trait magenta rendu avant l'appel au modèle. Le moteur GGUF ne charge pas cette LoRA. La compatibilité avec Consistency n'est pas documentée.

**Preuve disponible :** sur 160 paires, l'auteur annonce 64,4 % de détection de l'objet avec la LoRA à 40 étapes contre 66,9 % avec Qwen 2.1 seul et une instruction ordinaire. Avec Viggle Turbo à 6 étapes : 67,5 % contre 65,6 %. Le vote de réalisme par un VLM préfère la base 56 fois contre 44. Ces chiffres ne démontrent donc pas un gain général ; ils justifient surtout un essai du couple Doodle + Turbo et une comparaison avec le modèle de base sur les mêmes entrées.

**Points techniques à lever avant intégration :**

- Le fichier recommandé pour Diffusers est `doodle_in_lora_qwen21_gate_up_split.safetensors` (168 Mo). Le fichier original ComfyUI/ai-toolkit (159 Mo) perdrait silencieusement les poids `gate_up` lors d'un chargement Diffusers direct. Vérifier le chargement de 448 modules LoRA.
- La fiche dit que le checkpoint 500 a été retenu pour les mesures, tandis que le fichier Diffusers recommandé porte un nom sans suffixe de checkpoint. Vérifier précisément de quel checkpoint provient ce fichier avant de reproduire les chiffres.
- La démonstration Turbo emploie une Viggle `r256` ; NanoApple installe actuellement `r128`. Mesurer la qualité avec le paquet réellement utilisé par l'application avant d'annoncer le résultat de la fiche.
- Les essais publiés utilisent CUDA, `torch==2.14.0`, `transformers==5.17.0` et un commit Diffusers différent du commit épinglé par NanoApple. Tester le chargement et l'inférence en float16/MPS, notamment avec 24 et 64 Go de mémoire unifiée.
- La LoRA a été entraînée à 768 px. Tester 768 px et 1024 px, les tailles personnalisées et le maintien de l'arrière-plan ; surveiller les ombres de contact et les contours colorés restants.
- La licence Qwen Research annoncée par la fiche est réservée à la recherche et à l'évaluation non commerciales. Vérifier les conditions de distribution avant de la proposer dans un produit diffusé.

**Décision provisoire :** priorité moyenne pour un prototype local en mode Expert. Comparer d'abord Qwen seul, Qwen + LoRA, Viggle installé seul et Viggle installé + LoRA, avec mêmes images, tracés et graines. Ne proposer l'installation dans l'interface qu'après validation MPS, vérification du checkpoint et essai visuel des cas d'usage NanoApple.

## 2. ComfyUI v0.38.0 : fonctions Qwen 2.1 à examiner

Sources : [publication signalée](https://x.com/aiaicreate/status/2105087008490262953), [notes officielles v0.38.0](https://github.com/Comfy-Org/ComfyUI/releases/tag/v0.38.0), [cache KV](https://github.com/Comfy-Org/ComfyUI/pull/16429), [compilation des blocs](https://github.com/Comfy-Org/ComfyUI/pull/16430).

La publication résume une mise à jour de ComfyUI, pas un nouveau LoRA. NanoApple utilise Diffusers/MPS et `stable-diffusion.cpp`/Metal, pas ComfyUI. Les améliorations ComfyUI ne deviennent donc pas automatiquement disponibles dans l'application.

| Piste | Ce que montre la version 0.38.0 | Évaluation pour NanoApple |
| --- | --- | --- |
| Cache KV du préfixe Qwen 2.1 | ComfyUI améliore le choix mémoire GPU/RAM du cache pendant les étapes de retouche. Le PR montre 100 s à 24 s sur une configuration Windows/RTX 5080 à deux références, dans un cas auparavant limité par la mémoire. | Priorité haute pour *mesurer* le temps par étape et la mémoire avec plusieurs références sur MPS ; examiner ensuite l'équivalent dans le Diffusers épinglé. Ce chiffre ne prédit pas un gain sur Mac. |
| Compilation des blocs du transformeur | Optimisation propre au moteur ComfyUI et à son gestionnaire mémoire. L'exemple publié sur Linux/RTX 5090 passe de 87 s à 84 s. | Priorité basse à moyenne. Évaluer uniquement si le profilage NanoApple montre un goulot comparable et si une stratégie MPS est stable ; ne pas intégrer ComfyUI pour cette seule optimisation. |
| ControlNet Union Qwen 2.1 | La version inclut aussi [le support Qwen Fun ControlNet](https://github.com/Comfy-Org/ComfyUI/pull/16519), distinct du « Fun-Controlnet-Union 2.0 » annoncé pour MiniMax-H3 dans le post. | Fonction potentielle de contrôle spatial, mais nouveau modèle et nouveau chemin d'inférence. À instruire séparément après le dessin Doodle et les mesures de mémoire. |
| Tiny VAE Qwen 2.1 | La version ajoute [un encodeur/décodeur VAE approximatif](https://github.com/Comfy-Org/ComfyUI/pull/16552). | Piste d'aperçu rapide seulement, sous réserve de compatibilité avec Diffusers ou GGUF et d'une comparaison avec le VAE actuel, notamment pour l'alpha. |

La version corrige également [un problème de compilation en fp16](https://github.com/Comfy-Org/ComfyUI/pull/16608) dans son propre moteur. C'est un signal à surveiller puisque NanoApple exécute le transformeur et le VAE Diffusers en float16 sur MPS, sans démontrer que le même défaut touche NanoApple.

**Prochaine mesure utile :** enregistrer sur un même Mac et aux mêmes réglages le temps total, le temps par étape, le pic mémoire et la qualité pour création, retouche à une référence et retouche à plusieurs références. Ces données permettront de décider si le cache KV ou un autre moteur mérite une expérimentation.

## 3. Qwen-Image-2.1-Fix par e-n-v-y

Sources : [fiche du modèle](https://huggingface.co/e-n-v-y/Qwen-Image-2.1-Fix), [fichiers du dépôt](https://huggingface.co/e-n-v-y/Qwen-Image-2.1-Fix/tree/main) et [discussion sur les comparaisons](https://huggingface.co/e-n-v-y/Qwen-Image-2.1-Fix/discussions/1).

**Promesse :** une LoRA communautaire censée améliorer plusieurs défauts de génération de Qwen-Image 2.1 lorsqu'elle est utilisée avec les réglages de son workflow. La fiche montre des images comparatives, mais ne définit pas les défauts corrigés, ne donne pas de mesures chiffrées et ne précise pas clairement quel côté de chaque comparaison correspond à la LoRA. Le résultat affiché combine l'adaptateur et d'autres réglages ; leur contribution respective reste inconnue.

**Fichiers et compatibilité :** le dépôt contient actuellement `qwen-image-2.1-fix-1.0-comfy.safetensors` (112 Mo) et `Qwen Edit 2.1 Optimal Settings.json.zip` (7,17 Ko), mais aucun poids nommé pour Diffusers ni fichier de licence propre à ce dépôt. Le bloc d'exemple Diffusers de Hugging Face est générique : il ne prouve ni le chargement complet des poids ComfyUI ni un résultat sur MPS. Le moteur GGUF actuel ne charge pas de LoRA facultative.

**Vérification technique du 3 octobre :** lecture de l'en-tête safetensors par requête HTTP partielle, sans télécharger les poids complets. Il contient 396 tenseurs BF16, des matrices LoRA de rang 32 et des tenseurs `dora_scale`, notamment sur `img_mlp.gate_up`. Il faut donc vérifier le traitement **DoRA**, en plus de la séparation SwiGLU. Le convertisseur Consistency de NanoApple exige exactement ses paires A/B attendues et rejetterait ce fichier ; le recopier ou ignorer les échelles ne constitue pas une conversion fidèle. La compatibilité avec le chargeur Diffusers épinglé et PEFT reste à établir par un chargement réel.

**Workflow désormais vérifié directement :** le [ZIP de l'auteur](https://huggingface.co/e-n-v-y/Qwen-Image-2.1-Fix/blob/main/Qwen%20Edit%202.1%20Optimal%20Settings.json.zip) a été récupéré ; son SHA-256 correspond à celui affiché par Hugging Face : `551ddc7c724a79b91b15e7da135d67092a63c61686ae893dd49518af969e166f`. Le graphe connecte le modèle à la LoRA, puis à APG, FreSca et KSampler.

| Paramètre | Valeur du JSON |
| --- | --- |
| Adaptateur | Force 1 ; ancien nom `qwen-image-2.1-fix-1.0.safetensors`, à remplacer par le fichier actuel `-comfy` |
| KSampler | 20 étapes, CFG 3, `seeds_2`, `sgm_uniform`, denoise 1 |
| APG / FreSca | Valeurs de widgets `[1, 10, 0.3]` / `[1, 2, 8]` ; vérifier leurs noms et leur sémantique dans les versions des nœuds utilisées |
| Taille et graine connectée | 1200 × 1600 ; SeedNode fixé à 79, qui remplace la valeur locale affichée dans KSampler |
| Poids de base | Transformeur et encodeur Qwen3-VL en `int8_convrot`, VAE Qwen 2.1 BF16 |
| Prompt | Réécriture via TextGenerate en trois paragraphes avant encodage ; prompt négatif présent |
| Référence | LoadImage non connecté et entrée image de TextEncodeQwenImage21 vide : le graphe livré fait de la création malgré son nom « Edit » |

APG, FreSca et ce sampler ne sont pas exposés par le runtime NanoApple. Celui-ci utilise CFG 4 lorsqu'un prompt négatif est fourni. La largeur 1200 n'est pas acceptée par sa validation en multiples de 32. Le JSON conserve aussi des notes et un nom de sortie FLUX sans rapport avec les poids Qwen effectivement connectés : suivre le graphe, pas ces intitulés.

**Évaluation proposée :** comparer sur les mêmes prompts et graines (1) Qwen actuel, (2) Qwen avec les nouveaux réglages sans LoRA, (3) Qwen avec LoRA et réglages actuels lorsque ce chargement est techniquement valide, puis (4) Qwen avec LoRA et réglages recommandés. Juger couleurs, textures, mains, fidélité au prompt, variété, temps et mémoire, en création et en retouche. Examiner séparément la licence et la possibilité de distribuer ce poids.

**Décision provisoire :** priorité moyenne pour une étude de qualité, faible pour une intégration immédiate. Le gain propre à la LoRA et sa compatibilité Diffusers/MPS ne sont pas démontrés par les éléments publiés.

## 4. Viewpoint Orbit : changer l'angle d'un sujet transparent

Sources : [publication eternityspring](https://x.com/eternityspring/status/2105612902019547632), [publication citée sur les lunettes](https://x.com/eternityspring/status/2105084568131047553), [fiche technique](https://huggingface.co/ML-Intern-lab/Qwen-Image-2.1-viewpoint-orbit-LoRA).

Le premier post évoque une vidéo de tenues réalisée avec Opus 5.5 et Viewpoint Orbit. Le post cité annonce onze vues de lunettes transparentes. Cela documente un usage de montage ; la LoRA produit des images, sans preuve de génération vidéo continue ni de reconstruction 3D exacte.

**Usage documenté par le modèle :** une référence RGBA, rotations relatives avec préfixe `<orbit>`, 768 px, 40 étapes, CFG 1. L'adaptateur Diffusers recommandé est `checkpoints/steps2000res768/orbit_alpha_lora_gate_up_split.safetensors` (168 Mo), vérifié par l'auteur sur CUDA et un commit différent de NanoApple. Sur 160 retouches avec rendus de référence, l'alpha IoU passe de 0,727 à 0,794 et LPIPS de 0,097 à 0,090. L'entraînement porte sur des objets scannés ; les détails cachés, logos et éclairages peuvent dériver. Une démonstration de vêtements ne valide donc pas la fidélité des personnes.

**Obstacle identifié avant intégration :** `qwen_runtime.py` appliquait `.convert("RGB")` à toutes les références. Préserver l'alpha de bout en bout est un préalable à ce protocole. Il faudrait ensuite un choix d'angle, une seule référence, le chargement de l'adaptateur, CFG 1 et une génération par vue. Le backend GGUF refuse actuellement la transparence. La coexistence avec Viggle ou Consistency n'est pas validée.

**Implémentation du 3 octobre :** le mode Expert « Angle de vue » et l'installation facultative sont désormais ajoutés. Le chemin Orbit conserve le RGBA, ajuste la référence à 768 px sans déformation, fixe 40 étapes/CFG 1 et n'active aucun autre adaptateur. Les choix de caméra sont sauvegardés. L'en-tête du fichier recommandé contient 448 tenseurs F16 déjà séparés pour SwiGLU, mais préfixés `diffusion_model` ; le runtime vérifie chaque paire et son format puis la transmet à Diffusers sous le préfixe `transformer`. Le protocole CPU vérifie les 23 instructions Swift/Python, les entrées transparentes et le runner simulé. Aucune qualité d'inférence MPS n'est encore revendiquée.

**Décision : intégration Diffusers/MPS effectuée ; priorité haute pour la validation visuelle.** C'est une fonction nouvelle et contrôlable pour objets, accessoires et personnages. Commencer avec trois vues par sujet à 768 px, chacune depuis l'original, sans amélioration automatique du prompt ni autre adaptateur. Comparer à Qwen seul ; vérifier angle obtenu, alpha, silhouette, détails, temps et mémoire. Pour une fiche produit, faire contrôler chaque face inventée. Une planche de vues ou un GIF serait une fonction d'export distincte à examiner après validation des images.

## 5. Noct Q : transformeur dérivé orienté réalisme

Sources : [publication wildmindai](https://x.com/wildmindai/status/2105942320315302332), [fiche du modèle](https://huggingface.co/Noctaluna/Noct-Q-Uncensored-Qwen-Image-2.1?not-for-all-audiences=true), [fichiers](https://huggingface.co/Noctaluna/Noct-Q-Uncensored-Qwen-Image-2.1/tree/main).

**Nature :** transformeur modifié, pas LoRA. Le dépôt propose V4 et V3 en `int8_convrot`, environ 7,26 Go chacun, avec workflows ComfyUI ; la fiche renvoie les autres précisions vers Civitai. Elle recommande 25 étapes, Euler, scheduler `simple`, CFG 3 et 1024 × 1536. Le « trois fois plus » annoncé compare V4 à V3 sur des scènes adultes, sans protocole détaillé ; cela ne mesure pas un gain général face au Qwen officiel.

**Conséquence pour NanoApple :** ce fichier unique ComfyUI ne remplace directement ni le dossier Diffusers chargé par `from_pretrained`, ni le transformeur GGUF Q6. Une conversion ou des poids au format pris en charge seraient nécessaires, avec vérification de la quantification et des sorties MPS. Les 7,26 Go sont le poids du transformeur seul ; ils ne constituent pas la taille du pipeline ni une estimation de RAM Mac. Les indications de VRAM de la fiche ne s'appliquent pas directement à la mémoire unifiée.

Le code actuel dispose déjà d'une variante Heretic qui remplace **l'encodeur de texte** ; Noct Q intervient sur **le transformeur**. Leur apport respectif devrait être comparé sur les mêmes prompts ordinaires : portraits, vêtements, produits et texte. Le filtre NSFW de l'application est un classifieur après génération, indépendant du modèle utilisé.

**Décision : écarté à la demande de l'utilisateur le 3 octobre.** Le contenu adulte n'est pas la cible de NanoApple. Cette section reste uniquement une trace de l'analyse ; aucune intégration n'est prévue.

## 6. VAE HDR de Felldude : rendu accentué

Sources : [fiche](https://huggingface.co/Felldude/QWEN_2.1_HDR_VAE), [fichiers](https://huggingface.co/Felldude/QWEN_2.1_HDR_VAE/tree/main), [configuration HDR](https://huggingface.co/Felldude/QWEN_2.1_HDR_VAE/blob/main/config.json), [configuration du VAE officiel](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/vae/config.json).

**Nature et compromis :** VAE affiné de 1,35 Go en F32. L'auteur cherche à accentuer saturation, netteté et volume colorimétrique : SSIM 0,958 → 0,944 et PSNR 38,1 → 32 dB. Ces mesures concernent la reconstruction et ne démontrent pas une meilleure génération. La fiche ne précise ni le corpus complet ni sa taille ; elle annonce des essais autour de 512–1024 px et un alpha peu ajusté aux cas inhabituels. Aucun format de sortie HDR à luminance étendue n'est documenté.

**Vérification technique :** les deux `config.json` récupérés sont identiques : classe `AutoencoderKLQwenImage21`, quatre canaux en entrée/sortie, 64 canaux latents, compression spatiale ×16 et mêmes `latents_mean/std`. C'est un indice favorable à un remplacement expérimental du composant VAE Diffusers, sans garantir la stabilité des poids en float16/MPS. Le dépôt contient un VAE seul : l'exemple automatique Hugging Face qui le charge comme pipeline complet ne constitue pas une recette d'intégration.

**Conséquence produit :** NanoApple sauvegarde actuellement une image PIL en PNG ; le code examiné ne met en place aucune chaîne d'export HDR. Présenter cette option comme « rendu accentué » serait plus précis. En retouche, changer aussi l'encodeur VAE peut modifier la référence avant génération ; décoder les mêmes latents avec les deux VAE est le premier test qui isole leur effet. Le chemin GGUF utilise d'autres conventions de poids : son chargement reste à vérifier séparément.

**Décision : priorité moyenne pour un essai isolé, basse comme réglage par défaut.** Comparer couleurs de peau, aplats, contours alpha, détails et halos à 768/1024 px. Garder le VAE officiel pour les usages où la fidélité des couleurs et des produits compte. Le 2K et les associations avec les LoRA viennent après ces essais.

## 7. Ordre de travail proposé après cette fournée

1. **Orbit** : intégration ajoutée ; mesurer maintenant une petite série de vues sur MPS avec le modèle installé.
2. **VAE HDR** : comparer le décodage des mêmes latents, puis l'effet sur la retouche.
3. **Fix** : résoudre DoRA et reproduire le workflow avant d'attribuer un gain à l'adaptateur ; maintenir le même prompt développé entre variantes.

Orbit et Noct Q annoncent la licence Qwen Research ; le VAE HDR la déclare mais ne contient pas le fichier `LICENSE` auquel sa fiche renvoie. Fix n'affiche pas de licence propre dans les fichiers consultés. Le [texte officiel de Qwen 2.1](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE), §§1i et 2, limite les droits accordés à la recherche et à l'évaluation non commerciales, avec licence séparée pour l'usage commercial. Ce point concerne aussi le modèle de base déjà utilisé, pas seulement ces extensions. Clarifier les droits des auteurs et de Qwen avant une distribution commerciale ; cela n'empêche pas de poursuivre l'évaluation documentaire.
