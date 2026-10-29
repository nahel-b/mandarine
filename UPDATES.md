# Mises à jour automatiques par GitHub

Vous poussez une version sur GitHub ; chaque Mandarine installé la détecte, la télécharge, vérifie sa signature, se remplace et redémarre.

## Mise en place (une seule fois)

1. **Créer le dépôt GitHub** (public : l'app lit les releases sans identifiant) et y pousser le projet :
   ```bash
   git init && git add . && git commit -m "Mandarine"
   git branch -M main
   git remote add origin https://github.com/VOTRE_PSEUDO/mandarine.git
   git push -u origin main
   ```
2. **Clé de signature** : déjà créée sur ce Mac (`~/.mandarine/update_private_key`, jamais à publier). Sa partie publique est dans `Scripts/update_public_key.txt` (à pousser) et intégrée à l'app.
   Pour la refaire : `swift Scripts/update_tool.swift keygen` — mais les versions déjà installées ne pourraient plus se mettre à jour.
3. **Donner la clé privée à GitHub** : dépôt → Settings → Secrets and variables → Actions → *New repository secret* →
   nom `UPDATE_PRIVATE_KEY`, valeur = contenu de `~/.mandarine/update_private_key` (`cat ~/.mandarine/update_private_key | pbcopy`).
4. **Pour les builds faits sur ce Mac** (facultatif) : écrire `GITHUB_REPO=VOTRE_PSEUDO/mandarine` dans `Scripts/update.conf`.
   Les builds faits par GitHub Actions le renseignent tout seuls.

## Publier une version

```bash
Scripts/release.sh 1.1.0
```
Le script met à jour `VERSION`, crée l'étiquette `v1.1.0` et la pousse. GitHub Actions (`.github/workflows/release.yml`) compile l'app (Apple Silicon + Intel), la signe, et publie la release avec `Mandarine.zip`, `Mandarine.zip.sig` et `Mandarine.dmg`.
Les notes de version affichées aux utilisateurs viennent de la description de la release (première ligne).

## Côté utilisateur

- La première installation se fait avec le DMG d'une release (une version qui contient déjà ce système).
- Ensuite : **une vérification par jour au plus** (au lancement, au réveil du Mac, ou quand l'app tourne depuis plus de 24 h en heure réelle : les minuteurs ne comptent pas le temps de veille, on compare donc des dates). Un contrôle local toutes les heures ne fait que comparer des dates, sans réseau. « Check for updates » vérifie toujours tout de suite. Une pastille « Mandarine X.Y est disponible — Update » apparaît, ou l'installation se fait seule quand l'app est inactive (aucun travail en cours, aucune fenêtre d'outil ouverte).
- Une mise à jour trouvée mais pas encore installée (app occupée, puis quittée) est notée (`pendingUpdateVersion`) : au lancement suivant elle est reprise tout de suite, sans attendre 24 h. Une vérification qui échoue (réseau coupé) ne consomme pas le délai : le contrôle horaire réessaie. L'heure de la dernière vérification est affichée dans Réglages → Updates.
- Réglages → Updates : version, « Check for updates », et deux interrupteurs (vérification automatique, installation automatique). Menu de la barre : « Check for Updates… ».

## Sécurité

L'archive n'est installée que si sa signature Ed25519 correspond à la clé publique intégrée à l'app : même avec un accès au dépôt, personne ne peut pousser une fausse version sans la clé privée. En cas d'échec de la copie, l'ancienne app est restaurée.
L'app doit pouvoir se remplacer : elle doit se trouver dans un dossier modifiable par l'utilisateur (Applications convient s'il l'y a glissée).
