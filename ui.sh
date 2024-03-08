#!/usr/bin/env bash
printf "Bash version: %s\n" "$BASH_VERSION"
set -euo pipefail

export NG_CLI_ANALYTICS=false
# Get the current working directory
CURRENT_DIRECTORY=$(pwd)
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

pushd ${SCRIPT_PATH} >/dev/null
trap cleanup EXIT

function success() {
  echo -e "\x1B[32m$(</dev/stdin)\x1B[0m"
}

function warning() {
  echo -e "\x1B[33m$(</dev/stdin)\x1B[0m"
}

function error() {
  echo -e "\x1B[31m$(</dev/stdin)\x1B[0m"
}

function info() {
  echo -e "\x1B[34m$(</dev/stdin)\x1B[0m"
}

function titleCase() {
    # Read input from stdin
    while read -r line; do
        local string="$line"
        local result=""
        local word=""

        # Convert each word to title case
        for word in $string; do
            # Convert hyphens to spaces and capitalize each word
            result="$result $(echo "${word//-/ }" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1')"
        done

        # Remove leading whitespace
        result="${result## }"

        echo "$result"
    done
}

function should_continue() {
  # echo the first parameter in yellow color
  echo -e "\x1B[33m$1\x1B[0m"
  read -r CONTINUE
  if [[ "$CONTINUE" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Continuing..."
  else
    echo "Exiting..."
    exit 1
  fi
}

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
  local PROJECT_PATH="$CURRENT_DIRECTORY/$PROJECT_NAME"
  local UI_FOLDER_NAME=${2:-'ui'}
  local UI_PATH="$PROJECT_PATH/$UI_FOLDER_NAME"

  printf "destroying '%s' folder.\n" "$PROJECT_PATH"
  destroy "$PROJECT_PATH"

  printf "creating '%s' folder.\n" "$PROJECT_PATH"
  mkdir -p "$PROJECT_PATH"
  pushd "$PROJECT_PATH" >/dev/null
    save_exact
    echo -e "node_modules
  dist/
    " > ".gitignore"

    create_dockerfile "$PROJECT_NAME/$UI_FOLDER_NAME" # TODO: the docker file creation is not exactly the best yet.

    npm init -y
    npm install --save-exact --save-dev @angular/cli@latest
  popd >/dev/null

  printf "creating '%s' folder.\n" "$UI_PATH"
  mkdir -p "$UI_PATH"
  pushd "$UI_PATH" >/dev/null

  save_exact
  npx ng new "$UI_FOLDER_NAME" --ssr=false --directory ./ --routing --style=less --minimal --skip-tests --minimal --skip-git --strict
  npx ng add @angular-eslint/schematics --skip-confirmation --verbose
  npx ng add @cypress/schematic --skip-confirmation --e2e --verbose --interactive false

#  should_continue "Angular initiated. Setting up NG Zorro now. Do you want to continue? (Y/N)"
  npx ng add ng-zorro-antd@latest --skip-confirmation --verbose \
    --dynamic-icon \
    --skip-install \
    --template "sidemenu" \
    --theme \
    --project "$UI_FOLDER_NAME" \
    --locale "en_US"

  echo '@import "ng-zorro-antd/ng-zorro-antd.less";' >> "src/styles.less"
  (echo 'import { provideHttpClient } from "@angular/common/http";' && cat src/app/app.config.ts) > src/app/app.config.ts.tmp && mv src/app/app.config.ts.tmp src/app/app.config.ts
  (echo 'import { provideAnimations } from "@angular/platform-browser/animations";' && cat src/app/app.config.ts) > src/app/app.config.ts.tmp && mv src/app/app.config.ts.tmp src/app/app.config.ts
  sed -i '' -e 's/providers: \[provideRouter(routes), provideNzIcons()\]/providers: \[provideRouter(routes), provideNzIcons(), provideAnimations(), provideHttpClient()\]/' src/app/app.config.ts

  # replace text 'Ant Design Of Angular' with $PROJECT_NAME
  local PROJECT_NAME_TITLE=$(echo "$PROJECT_NAME" | titleCase)
  echo "Replacing 'Ant Design Of Angular' with '$PROJECT_NAME_TITLE' ..."
  sed -i '' -e "s/Ant Design Of Angular/$PROJECT_NAME_TITLE/ig" src/app/app.component.html

  popd

  echo "✔ All done. Starting ui server from the folder of '$PROJECT_NAME/$UI_FOLDER_NAME' ...\n" | success
  start "$CURRENT_DIRECTORY/$PROJECT_NAME/$UI_FOLDER_NAME"
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
