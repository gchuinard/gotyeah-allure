# CLAUDE.md — gotyeah-allure

Dashboard de tests centralisé **Allure Report (OSS)** pour la flotte GotYeah. Agrège les résultats Playwright + pytest de tous les repos dans un rapport unifié servi sur le Pi derrière NPM + Cloudflare Access.

## Ce que contient ce repo
- `actions/push-allure-results/` — composite action GitHub réutilisée par chaque repo testé : injecte le label `parentSuite=<site>` dans les `*-result.json` puis rsync vers le Pi.
- `pi/` — service déployé sur le Pi : `allure-generator` (watch + `allure generate` multi-dossiers + history) et `allure-web` (nginx). Données dans `/home/pi/allure/{results,history,report}`.
- `snippets/` — extraits CI de référence (pytest / Playwright).
- `.github/workflows/deploy.yml` — déploie `pi/` (rsync + `docker compose up -d --build`).

## Invariants à respecter
- **Clé de site = nom du repo GitHub** (ex. dossier `gotyeah_sonar` → repo/site `gotyeah-sonar`).
- Collecte **branche `main` uniquement**, étape `if: always()` (on garde les échecs).
- Le label site est injecté **côté action**, pas dans les specs/tests → ne pas modifier les tests pour ça.
- Tous les fichiers de résultats Allure sont UUID-nommés → l'agrégation multi-sites ne collisionne pas. Ne pas pousser `categories.json`/`environment.properties`/`executor.json` (noms fixes → collisions au merge).
- E2E = **DB jetable isolée**, jamais la prod.

## Commandes
- Régénérer à la main : `docker exec allure_generator generate.sh`
- Logs : `docker logs -f allure_generator`

Détails complets : `README.md`. Contexte d'audit : `../ALLURE_AUDIT.md`.
