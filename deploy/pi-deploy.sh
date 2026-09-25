#!/bin/bash
# Déploiement de l'agrégateur Allure sur le Pi. Ce script ne se lance pas à la main : il est
# exécuté par /usr/local/sbin/gotyeah-deploy (commande forcée de la clé
# DEPLOY_SSH_KEY dans authorized_keys), juste après le git pull de main, depuis
# /home/pi/deploiement/gotyeah-allure (copie de ce dépôt public). Argument : le commit déployé avant celui-ci.
# Modifier ce fichier suffit : le prochain déploiement lance la version de main.
set -euo pipefail

# pi/ devient le dossier du service, comme le faisait l'ancien rsync depuis GitHub.
# Les droits d'écriture du groupe et des autres sont retirés au passage.
cible=/home/pi/sites/gotyeah-allure
rsync -a --delete --chmod=Dgo-w,Fgo-w pi/ "$cible/"

mkdir -p /home/pi/allure/results /home/pi/allure/history /home/pi/allure/report
cd "$cible"
docker compose up -d --build
docker image prune -f
