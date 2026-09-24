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

1. **Créer + pousser ce repo** sur GitHub : `gchuinard/gotyeah-allure` (branche `main`). L'action est référencée par les autres repos via `gchuinard/gotyeah-allure/actions/push-allure-results@<SHA complet>` (`8df4d1f7f8dbc77ccc585c58b00b8cb7733c20fc` depuis le 24/09/2026 au soir : l'action reçoit les clés d'hôte du Pi par l'input obligatoire `ssh-known-hosts` et échoue s'il est vide). Elle l'était d'abord par `@main`, ce qui faisait exécuter tout nouveau commit de ce dépôt avec la clé SSH de chaque CI : toute modification de l'action impose donc de refiger ces références sur le nouveau SHA. Cette ligne donnait ensuite le commit `2610fcd0d507e8bb31c1334c76c65745607740f8` (même jour), premier où l'action vérifiait la clé d'hôte du Pi au lieu d'accepter la première présentée : il le faisait avec les clés d'hôte écrites en clair dans `action.yml`, ce qui, dans un dépôt public, permet de retrouver l'adresse du Pi dans les bases de scan (Censys, Shodan). Elles viennent désormais d'un secret (étape 3), mais restent lisibles dans l'historique git de ce commit.
2. **Autoriser l'accès à l'action depuis les autres repos** : repo `gotyeah-allure` → *Settings → Actions → General → Access* → **« Accessible from repositories owned by gchuinard »**. (Sinon les CI échouent avec « action not found » sur un repo privé.)
3. **Secrets** : chaque repo instrumenté doit avoir `SSH_HOST`, `SSH_USER`, `SSH_KEY` (et `SSH_PORT` si ≠ 22). La plupart les ont déjà pour leur déploiement — vérifier les **noms** (certains repos utilisent `DEPLOY_HOST/USER/KEY` : adapter le `with:` de l'action).
   Depuis le 24/09/2026, il faut aussi **`SSH_KNOWN_HOSTS`** dans chaque dépôt appelant (et dans celui-ci, que `deploy.yml` utilise) : les clés d'hôte publiques du Pi, une par ligne au format known_hosts, sous l'alias `pi-gotyeah`, passées à l'action par `ssh-known-hosts: ${{ secrets.SSH_KNOWN_HOSTS }}`. L'action refuse de pousser si elles manquent, et la connexion échoue si le Pi présente une autre clé. Jamais en clair dans un workflow ni dans la doc d'un dépôt public. Pour produire la valeur, sur le Pi (elle se lit dans les fichiers de l'hôte, sans passer par le réseau) :
   ```bash
   for f in /etc/ssh/ssh_host_*_key.pub; do printf 'pi-gotyeah %s\n' "$(cut -d' ' -f1,2 "$f")"; done
   ```
   puis la coller dans *Settings → Secrets and variables → Actions* du dépôt appelant, ou `gh secret set SSH_KNOWN_HOSTS -R gchuinard/<dépôt>` qui la lit sur l'entrée standard.
4. **Déployer le service** : pousser `main` (le workflow `deploy.yml` rsync `pi/` vers `/home/pi/sites/gotyeah-allure` et lance `docker compose up -d --build`), ou manuellement sur le Pi :
   ```bash
   mkdir -p /home/pi/allure/{results,history,report}
   cd /home/pi/sites/gotyeah-allure && docker compose up -d --build
   ```
5. **NPM** : nouveau Proxy Host (ex. `allure.<domaine>`) → `http://allure_web:80`, le conteneur étant attaché au réseau NPM (cf. §6). Certificat via Cloudflare. CSP en base NPM comme les autres sites. Cette étape proposait d'abord `http://<pi-host>:8095` : ce n'est plus possible depuis le 24/09/2026, le port 8095 n'est publié que sur 127.0.0.1 du Pi (sur toutes les interfaces, il exposait le rapport au réseau local sans passer par NPM).
6. **Cloudflare Access** : application self-hosted sur `allure.<domaine>`, méthode **One-time PIN**, policy *Allow* limitée à ton e-mail. → code à 6 chiffres par mail, aucun mot de passe.

## 4. Brancher un repo (contrat)

Voir `snippets/`. En résumé :

| Type | À ajouter | Commande de test | `site:` |
|---|---|---|---|
| pytest (uv) | `allure-pytest` (dev) | `uv run pytest --alluredir=allure-results` | nom du repo |
| pytest (pip) | `allure-pytest` (requirements-dev) | `python3 -m pytest --alluredir=allure-results` | nom du repo |
| Playwright | `allure-playwright` (devDep) + reporter dans `playwright.config.ts` | `npm run test:e2e` / `pnpm e2e` | nom du repo |

Puis l'étape `Publish Allure results` (action `push-allure-results`, figée sur le SHA complet de l'étape 1 du §3, avec `ssh-known-hosts: ${{ secrets.SSH_KNOWN_HOSTS }}`), **gardée sur `main`** et en `if: always()` (on veut aussi voir les échecs). Monorepos : un `suite:` par service (`api`/`core`/`worker`).

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
- **Proxy par nom de conteneur (seule voie depuis le 24/09/2026 : le port 8095 n'écoute plus que sur 127.0.0.1)** : `allure-web` est attaché au réseau `nginx-proxy-manager_default` (bloc `networks: npm`, external, de `docker-compose.yml`) et NPM pointe sur `http://allure_web:80`. Cette ligne demandait d'abord de décommenter ce bloc et d'y mettre le vrai nom du réseau : c'est fait depuis le 30/06/2026 (commit d128751).

## 7. Sécurité / données

- Le rapport peut exposer des détails techniques → **toujours derrière Cloudflare Access**.
- Les tests E2E utilisent des **DB jetables isolées** (jamais la prod). Vérifié pour yoga (`e2e/e2e.db`) et billetterie (SQLite seedée par `global-setup`).
- Aucun secret n'est stocké dans les résultats ; l'action n'écrit que des labels + le SHA court.
- **Clés d'hôte du Pi** : ni les clés ni leurs empreintes ne figurent en clair dans ce dépôt ou dans un autre dépôt public, car elles permettent de retrouver l'adresse du Pi dans les bases de scan. L'action et `deploy.yml` les lisent dans le secret `SSH_KNOWN_HOSTS` et exigent qu'elles correspondent (`StrictHostKeyChecking=yes`, alias `pi-gotyeah`). Le commit `2610fcd` les avait écrites dans `action.yml` : elles restent dans l'historique git public.
