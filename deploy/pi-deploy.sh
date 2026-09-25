#!/bin/bash
# Déploiement de l'agrégateur Allure sur le Pi. Ce script ne se lance pas à la main : il est
# exécuté par /usr/local/sbin/gotyeah-deploy (commande forcée de la clé
# DEPLOY_SSH_KEY dans authorized_keys), depuis /home/pi/deploiement/gotyeah-allure (copie de ce dépôt public), après un git fetch.
# Variables reçues : CIBLE (commit à déployer), AVANT (commit en place).
# Le script est lu dans le commit CIBLE : le modifier sur main suffit.
set -euo pipefail

git merge --ff-only "$CIBLE"

# pi/ devient le dossier du service, comme le faisait l'ancien rsync depuis GitHub.
# Les droits d'écriture du groupe et des autres sont retirés au passage.
cible=/home/pi/sites/gotyeah-allure
rsync -a --delete --chmod=Dgo-w,Fgo-w pi/ "$cible/"

mkdir -p /home/pi/allure/results /home/pi/allure/history /home/pi/allure/report
cd "$cible"
docker compose up -d --build
docker image prune -f
