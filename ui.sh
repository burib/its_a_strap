#!/usr/bin/env bash
printf "Bash version: %s\n" "$BASH_VERSION"
set -euo pipefail

export NG_CLI_ANALYTICS=false
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

pushd ${ROOT_DIR} >/dev/null
trap cleanup EXIT

function cleanup() {
  popd >/dev/null
}

function destroy() {
  local DIRECTORY=$1

  rm -rf "$DIRECTORY"
}

function create_dockerfile() {
  local PROJECT_NAME=$1
  local AUTHOR=$(git config user.name)

  echo -e "FROM cimg/node:lts-browsers
LABEL author=\"$AUTHOR\"
WORKDIR ./$PROJECT_NAME
USER root
RUN sudo apt-get update && sudo apt-get install curl jq -y
EXPOSE 4200
RUN npm ci
#RUN [\"ng\", \"serve\", \"-H\", \"0.0.0.0\"]
" > Dockerfile
}

function save_exact() {
  echo "save-exact=true" > .npmrc
}

function init() {
  local PROJECT_NAME=$1
  local UI_FOLDER_NAME=${2:-'ui'}

  printf "creating '%s' folder.\n" "$PROJECT_NAME"
  mkdir -p "$PROJECT_NAME"
  pushd "$PROJECT_NAME" >/dev/null
    save_exact
    echo -e "node_modules
  dist/
    " > ".gitignore"

    create_dockerfile "$PROJECT_NAME/$UI_FOLDER_NAME" # TODO: the docker file creation is not exactly the best yet.

    npm init -y
    npm install --save-exact --save-dev @angular/cli@latest
  popd >/dev/null

  printf "creating '%s' folder.\n" "$PROJECT_NAME/$UI_FOLDER_NAME"
  mkdir -p "$PROJECT_NAME/$UI_FOLDER_NAME"
  pushd "$PROJECT_NAME/$UI_FOLDER_NAME" >/dev/null

  save_exact
  npx ng new "$UI_FOLDER_NAME" --directory ./ --routing --style=less --verbose --minimal --skip-tests --minimal --skip-git --strict
  npx ng add @angular-eslint/schematics --skip-confirmation --verbose
  npx ng add @cypress/schematic --skip-confirmation --e2e-update --verbose

  npx ng add ng-zorro-antd@latest --skip-confirmation --verbose \
    --dynamic-icon true \
    --skip-install true \
    --template sidemenu \
    --theme true \
    --project "$UI_FOLDER_NAME" \
    --locale "en_US"

  popd

  printf "✔ All done. Starting ui server from the folder of '%s' ...\n" "\x1B[32m" "$PROJECT_NAME/$UI_FOLDER_NAME"
  start "$PROJECT_NAME/$UI_FOLDER_NAME"
}

function generate_page() {
  local PAGE_NAME=$1
  ng g m "pages/$PAGE_NAME" --routing --route "$PAGE_NAME" --module app.module
  ng g c ""
}

function start() {
  # TODO: add an option to start it as docker or not.
  local DIRECTORY=$1

  pushd "$DIRECTORY" >/dev/null

  npx ng serve --verbose --open

  popd
}

"$@"
