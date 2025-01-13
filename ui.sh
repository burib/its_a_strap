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
  echo -e "\x1B[32m$1\x1B[0m"
}

function warning() {
  echo -e "\x1B[33m$1\x1B[0m"
}

function error() {
  echo -e "\x1B[31m$1\x1B[0m"
}

function info() {
  echo -e "\x1B[34m$1\x1B[0m"
}
#function info() {
#  echo -e "\x1B[34m$(</dev/stdin)\x1B[0m"
#}

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
  # read PROJECT_NAME from terminal using read, should default to hq-app
  local PROJECT_NAME=${1:-'hq-app'}
  read -e -p "Enter Your Project Folder Name:" -i "$PROJECT_NAME" PROJECT_NAME # read the project name from the terminal
  info "Project name: $PROJECT_NAME"
  local PROJECT_NAME_TITLE=$(echo "$PROJECT_NAME" | titleCase)

  local PROJECT_PATH="$CURRENT_DIRECTORY/$PROJECT_NAME"
  local UI_FOLDER_NAME=${2:-'ui'}
  local UI_PATH="$PROJECT_PATH/$UI_FOLDER_NAME"

  printf "destroying '%s' folder.\n" "$PROJECT_PATH"
  info "destroying '$PROJECT_PATH' folder.\n"
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

  info "NG setup done. Adding NG Zorro ..."
  npx ng add ng-zorro-antd@latest --skip-confirmation --verbose \
    --dynamic-icon \
    --skip-install \
    --template "sidemenu" \
    --theme \
    --project "$UI_FOLDER_NAME" \
    --locale "en_US"

  info "NG Zorro setup done."

  local ICONS_PROVIDER_FILE_CONTENT=$(cat <<'EOF'
import { IconDefinition } from '@ant-design/icons-angular';
import { NzIconModule,provideNzIcons } from 'ng-zorro-antd/icon';

import { MenuFoldOutline, MenuUnfoldOutline, FormOutline, DashboardOutline } from '@ant-design/icons-angular/icons';

const icons: IconDefinition[] = [MenuFoldOutline, MenuUnfoldOutline, DashboardOutline, FormOutline];

export const iconsProvider = provideNzIcons(icons);
EOF
)

  local APP_CONFIG_SERVICE_FILE_CONTENT=$(cat <<'EOF'
import { Injectable } from '@angular/core';
import { ConfigModel } from "./app.config";
@Injectable({
  providedIn: 'root'
})

export class AppConfigService {
  config: ConfigModel;

  setConfig(config: ConfigModel | undefined) {
    if (config === undefined) {
      throw new Error('Config is null or undefined');
    } else {
      this.config = config;
    }
  }
  getConfig() {
    return this.config;
  }
  constructor() {
    this.config = {
      "restApiEndpoint": "http://localhost:8080",
      "loginUrl": "http://localhost:8080/login",
      "logoutUrl": "http://localhost:8080/logout",
      "refreshUrl": "http://localhost:8080/refresh",
      "tokenUrl": "http://localhost:8080/token",
      "clientId": "randomClientId"
    };
  }
}
EOF

)
  info "Creating app.config.service.ts file ..."
  echo "$APP_CONFIG_SERVICE_FILE_CONTENT" > src/app/app.config.service.ts

  local APP_CONFIG_FILE_CONTENT=$(cat <<'EOF'
import { provideAnimations } from "@angular/platform-browser/animations";
import { HttpClient, provideHttpClient} from "@angular/common/http";

import { APP_INITIALIZER, ApplicationConfig, provideZoneChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';

import { routes } from './app.routes';
import { iconsProvider } from './icons-provider';
import {AppConfigService} from "./app.config.service";
export interface ConfigModel {
  restApiEndpoint: string;
  loginUrl: string;
  logoutUrl: string;
  refreshUrl: string;
  tokenUrl: string;
  clientId: string;
}
export function initializeApp(http: HttpClient, configService: AppConfigService) {
  return async () => {
    const configPath = 'assets/config.json';
    await http.get<ConfigModel>(configPath).toPromise().then(
        response => {
          configService.setConfig(response);
        },
        error => {
          const errorMessage = `Failed to load the app config from ${configPath}.
            Please create ${configPath} and make sure it contains the app config.
            The app config should be a JSON file with the following structure:
            {
              "restApiEndpoint": "http://localhost:8080",
              "loginUrl": "http://localhost:8080/login",
              "logoutUrl": "http://localhost:8080/logout",
              "refreshUrl": "http://localhost:8080/refresh",
              "tokenUrl": "http://localhost:8080/token",
              "clientId": "randomClientId"
            }
            `;
          console.error('Failed to load the app config', error);
          throw new Error(errorMessage);
        }
    );
  };
}
export const appConfig: ApplicationConfig = {
  providers: [provideZoneChangeDetection({ eventCoalescing: true }), provideRouter(routes), iconsProvider, provideAnimations(), provideHttpClient(), AppConfigService, {
    provide: APP_INITIALIZER,
    useFactory: initializeApp,
    multi: true,
    deps: [HttpClient, AppConfigService],
  }],
};

EOF
)
  info "Creating app.config.ts file ..."
  echo "$APP_CONFIG_FILE_CONTENT" > src/app/app.config.ts

  local CONFIG_JSON_CONTENT=$(cat <<'EOF'
{
  "restApiEndpoint": "http://localhost:8080",
  "loginUrl": "http://localhost:8080/login",
  "logoutUrl": "http://localhost:8080/logout",
  "refreshUrl": "http://localhost:8080/refresh",
  "tokenUrl": "http://localhost:8080/token",
  "clientId": "randomClientId"
}
EOF
)
  info "Creating icons-provider.ts file ..."
  echo "$ICONS_PROVIDER_FILE_CONTENT" > src/app/icons-provider.ts

  info "Creating config.json file in 'public/assets' folder ..."
  mkdir -p public/assets
  echo "$CONFIG_JSON_CONTENT" > public/assets/config.json

  # replace text 'Ant Design Of Angular' with $PROJECT_NAME
  echo "Replacing 'Ant Design Of Angular' with '$PROJECT_NAME_TITLE' ..."
  sed -i '' -e "s/Ant Design Of Angular/$PROJECT_NAME_TITLE/ig" src/app/app.component.html

  info "Replacing <title> in src/index.html ..."
  sed -i '' -e "s/<title>Ui<\/title>/<title>$PROJECT_NAME_TITLE<\/title>/ig" src/index.html

  local STYLESS_DOT_LESS_FILE_CONTENT=$(cat <<'EOF'
/* You can add global styles to this file, and also import other style files */
@import "ng-zorro-antd/ng-zorro-antd.less";

nz-layout.ant-layout.app-layout {
  height: auto;
  min-height: 100vh;
}
EOF
)

  info "Creating styles.less file ..."
  echo "$STYLESS_DOT_LESS_FILE_CONTENT" > src/styles.less

  popd

  success "✔ All done. Starting ui server from the folder of '$PROJECT_NAME/$UI_FOLDER_NAME' ...\n"
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
