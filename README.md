# gotyeah-allure — Dashboard de tests centralisé (Allure OSS)

Agrège dans **un seul rapport Allure unifié** les tests **E2E Playwright** et **API/unit pytest** de tous les repos GotYeah, hébergé sur le Pi derrière Nginx Proxy Manager + Cloudflare.

> Conçu en Phase 2 du chantier `ALLURE_AUDIT.md` (à la racine du dossier parent). Allure était absent des 17 repos → tout est neuf ici.

## 1. Comment ça marche

```
[CI repo A] pytest/playwright --(allure-results)──┐
[CI repo B] ...                                    ├─ action push-allure-results ─ rsync/ssh ─┐
[CI repo N] ...                                    ┘   (injecte le label parentSuite=site)     │
                                                                                               ▼
                                                              Pi:/home/pi/allure/results/<site>/
                                                                                               │  (inotify + heartbeat)
                                                              [conteneur allure-generator]
                                              restaure history → allure generate (multi-dossiers) → report/  (swap atomique)
                                                                                               │
                                                              [conteneur allure-web (nginx)] :8095
                                                                          │
                                                NPM (proxy host) ── Cloudflare Access (One-time PIN) ── allure.<domaine>
```

- **Chaque CI** lance ses tests avec un reporter Allure (`--alluredir` / reporter `allure-playwright`) puis appelle l'action **`push-allure-results`** : elle **injecte le label `parentSuite = <site>`** dans chaque `*-result.json` (mécanisme unique pytest + Playwright, **zéro modif des specs/tests**) et **rsync** les résultats vers `/home/pi/allure/results/<site>/`.
- **Le Pi** fait tourner `allure-generator` : il **surveille** le dossier `results/` (inotify + heartbeat 15 min), **restaure l'historique** persistant, génère **un rapport unifié** (`allure generate` multi-dossiers) et le **bascule atomiquement** dans `report/`.
- **`allure-web`** (nginx) sert `report/` ; **NPM + Cloudflare Access** le protègent (code par e-mail, sans mot de passe).

Décisions actées (voir `ALLURE_AUDIT.md §4`) : rapport unifié unique · périmètre Playwright + pytest · auth OTP e-mail · store **filesystem** (pas MinIO) · collecte **branche `main`** · génération **watch-sur-push + heartbeat**.

## 2. Arborescence

```
gotyeah-allure/
├── actions/push-allure-results/action.yml   # composite action réutilisée par chaque repo
├── pi/                                       # service déployé sur le Pi
│   ├── docker-compose.yml                    # allure-generator + allure-web
│   ├── Dockerfile.generator                  # JRE + Allure CLI + inotify-tools
│   ├── generate.sh                           # agrège + restaure history + génère (locké)
│   ├── watch.sh                              # inotify + heartbeat → generate.sh
│   └── nginx.conf
├── snippets/                                 # extraits CI de référence (pytest / playwright)
└── .github/workflows/deploy.yml              # déploie pi/ sur le Pi (rsync + docker compose)
```

Données runtime sur le Pi (hors repo) : `/home/pi/allure/{results,history,report}`.

## 3. Bootstrap (ordre important)

1. **Créer + pousser ce repo** sur GitHub : `gchuinard/gotyeah-allure` (branche `main`). L'action est référencée par les autres repos via `gchuinard/gotyeah-allure/actions/push-allure-results@main`.
2. **Autoriser l'accès à l'action depuis les autres repos** : repo `gotyeah-allure` → *Settings → Actions → General → Access* → **« Accessible from repositories owned by gchuinard »**. (Sinon les CI échouent avec « action not found » sur un repo privé.)
3. **Secrets** : chaque repo instrumenté doit avoir `SSH_HOST`, `SSH_USER`, `SSH_KEY` (et `SSH_PORT` si ≠ 22). La plupart les ont déjà pour leur déploiement — vérifier les **noms** (certains repos utilisent `DEPLOY_HOST/USER/KEY` : adapter le `with:` de l'action).
4. **Déployer le service** : pousser `main` (le workflow `deploy.yml` rsync `pi/` vers `/home/pi/sites/gotyeah-allure` et lance `docker compose up -d --build`), ou manuellement sur le Pi :
   ```bash
   mkdir -p /home/pi/allure/{results,history,report}
   cd /home/pi/sites/gotyeah-allure && docker compose up -d --build
   ```
5. **NPM** : nouveau Proxy Host (ex. `allure.<domaine>`) → `http://<pi-host>:8095` (ou `http://allure_web:80` si tu attaches le conteneur au réseau NPM, cf. §6). Certificat via Cloudflare. CSP en base NPM comme les autres sites.
6. **Cloudflare Access** : application self-hosted sur `allure.<domaine>`, méthode **One-time PIN**, policy *Allow* limitée à ton e-mail. → code à 6 chiffres par mail, aucun mot de passe.

## 4. Brancher un repo (contrat)

Voir `snippets/`. En résumé :

| Type | À ajouter | Commande de test | `site:` |
|---|---|---|---|
| pytest (uv) | `allure-pytest` (dev) | `uv run pytest --alluredir=allure-results` | nom du repo |
| pytest (pip) | `allure-pytest` (requirements-dev) | `python3 -m pytest --alluredir=allure-results` | nom du repo |
| Playwright | `allure-playwright` (devDep) + reporter dans `playwright.config.ts` | `npm run test:e2e` / `pnpm e2e` | nom du repo |

Puis l'étape `Publish Allure results` (action `push-allure-results`), **gardée sur `main`** et en `if: always()` (on veut aussi voir les échecs). Monorepos : un `suite:` par service (`api`/`core`/`worker`).

**Clé de site = nom du repo GitHub** : `gotyeah-yoga`, `gotyeah-danse`, `gotyeah-sonar` (⚠️ le dossier local `gotyeah_sonar` → repo `gotyeah-sonar`), `gotyeah-QAIA`, `gotyeah-datagit`, `gotyeah-meteo`, `gotyeah-starter`, `gotyeah-stack`.

## 5. Périmètre actuel des sites collectés

| Site | Framework | Tests | Note |
|---|---|---|---|
| gotyeah-sonar | pytest | 37 | la suite tourne déjà en CI |
| gotyeah-stack | pytest (api/core/worker) | 49 | un `suite:` par service |
| gotyeah-QAIA | pytest | 7 | |
| gotyeah-datagit | pytest | 4 | |
| gotyeah-meteo | pytest (backend) | 1 | |
| gotyeah-starter | pytest | 1 | |
| gotyeah-yoga | Playwright | 4 | **tests ajoutés en CI** (n'y tournaient pas) — DB e2e isolée |
| gotyeah-danse | Playwright (billetterie) | 12 | **tests ajoutés en CI** — SQLite jetable seedée |

Hors périmètre (décidé) : Vitest (danse/billetterie 38, stack/web 7) ; repos sans tests (cf. `ALLURE_AUDIT.md §2`).

## 6. Exploitation

- **Forcer une régénération** : `docker exec allure_generator generate.sh`
- **Logs** : `docker logs -f allure_generator`
- **Réinitialiser les tendances** : vider `/home/pi/allure/history/` puis régénérer.
- **Rétention** : Allure garde ~20 builds d'historique pour les courbes ; surveiller la taille des attachements Playwright (`du -sh /home/pi/allure`). Garder `trace`/`video` sur échec uniquement.
- **Proxy par nom de conteneur (alternative au port 8095)** : décommenter le bloc `networks: npm (external)` dans `docker-compose.yml`, mettre le vrai nom (`docker network ls`), ajouter `networks: [npm]` à `allure-web`, et pointer NPM sur `http://allure_web:80`.

## 7. Sécurité / données

- Le rapport peut exposer des détails techniques → **toujours derrière Cloudflare Access**.
- Les tests E2E utilisent des **DB jetables isolées** (jamais la prod). Vérifié pour yoga (`e2e/e2e.db`) et billetterie (SQLite seedée par `global-setup`).
- Aucun secret n'est stocké dans les résultats ; l'action n'écrit que des labels + le SHA court.
