#!/usr/bin/env bash
printf "Bash version: %s\n" "$BASH_VERSION"

export NG_CLI_ANALYTICS=false
# Get the current working directory
CURRENT_DIRECTORY=$(pwd)
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

pushd "${SCRIPT_PATH}" >/dev/null
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
  else:
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
WORKDIR ./${PROJECT_NAME}
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

function create_fake_json_server() {
  local PROJECT_PATH=$1
  local SERVER_DIR="$PROJECT_PATH/fake-json-server"

  info "Creating fake JSON server at $SERVER_DIR"
  mkdir -p "$SERVER_DIR"
  pushd "$SERVER_DIR" >/dev/null

  # Initialize package.json
  npm init -y

  #    # Install json-server
  #    npm install --save-exact json-server

  # Create initial db.json with todo-app data
  local DB_JSON_CONTENT=$(cat <<'EOF'
{
  "todos": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "userId": "TEST_USER",
      "title": "Learn Angular",
      "description": "Complete the Angular tutorial",
      "dueDate": "2026-02-01",
      "status": "pending",
      "createdAt": "2024-01-15T10:00:00Z",
      "updatedAt": "2024-01-15T10:00:00Z"
    },
    {
      "id": "123e4567-e89c-12d3-a456-426614174000",
      "userId": "TEST_USER",
      "title": "Learn NgZorro",
      "description": "Complete the NgZorro tutorial",
      "dueDate": "2026-02-01",
      "status": "pending",
      "createdAt": "2024-01-15T10:00:00Z",
      "updatedAt": "2024-01-15T10:00:00Z"
    },
    {
      "id": "123e4567-e89d-12d3-a456-426614174000",
      "userId": "TEST_USER",
      "title": "Build an awesome app",
      "description": "Build an awesome app using Angular and NgZorro",
      "dueDate": "2026-02-01",
      "status": "pending",
      "createdAt": "2024-01-15T10:00:00Z",
      "updatedAt": "2024-01-15T10:00:00Z"
    }
  ],
  "users": [
    { "id": "TEST_USER", "name": "Test User", "email": "test.user@example.com" },
    { "id": 2, "name": "Jane Smith", "email": "jane@example.com" }
  ],
  "profile": {
    "name": "Demo User",
    "email": "demo@example.com",
    "avatar": "https://placekitten.com/200/200"
  }
}
EOF
)
  echo "$DB_JSON_CONTENT" > db.json
  popd >/dev/null
}

function create_todo_model() {
  local TODO_COMPONENTS_DIRECTORY=$1
  local TODO_MODEL_CONTENT=$(cat <<'EOF'
export interface Todo {
  id: string;
  userId: string;
  title: string;
  description: string;
  dueDate: Date;
  status: 'pending' | 'completed';
  createdAt: string;
  updatedAt: string;
  ttl?: number;
}

export type CreateTodoDto = Omit<Todo, 'id' | 'userId' | 'createdAt' | 'updatedAt' | 'ttl'>;
export type UpdateTodoDto = Partial<CreateTodoDto>;
EOF
)
  echo "$TODO_MODEL_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/state/todo.model.ts"
}

function create_todo_service() {
  local TODO_COMPONENTS_DIRECTORY=$1
  local TODO_SERVICE_CONTENT=$(cat <<'EOF'
import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Todo, CreateTodoDto, UpdateTodoDto } from './todo.model';
import { AppConfigService } from '../../../app.config.service';

@Injectable({
  providedIn: 'root'
})
export class TodoService {
  private http = inject(HttpClient);
  private config = inject(AppConfigService);
  private baseUrl = `${this.config.getConfig().restApiEndpoint}/todos`

  getTodos(): Observable<Todo[]> {
    return this.http.get<Todo[]>(this.baseUrl);
  }

  getTodoById(id: string): Observable<Todo> {
    return this.http.get<Todo>(`${this.baseUrl}/${id}`);
  }

  createTodo(todo: CreateTodoDto): Observable<Todo> {
    return this.http.post<Todo>(this.baseUrl, todo);
  }

  updateTodo(id: string, updates: UpdateTodoDto): Observable<Todo> {
    return this.http.patch<Todo>(`${this.baseUrl}/${id}`, updates);
  }

  deleteTodo(id: string): Observable<void> {
    return this.http.delete<void>(`${this.baseUrl}/${id}`);
  }
}
EOF
)
  echo "$TODO_SERVICE_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/state/todo.service.ts"
}

function create_todo_routes() {
    local TODO_COMPONENTS_DIRECTORY=$1

    # Create Todo routes
    local TODO_ROUTES_CONTENT=$(cat <<'EOF'
import { Routes } from '@angular/router';
import { TodoListComponent } from './todo-list.component';
import { TodoService } from './state/todo.service';
import { TodoFormComponent } from './todo-form.component';

export const TODO_ROUTES: Routes = [
  {
    path: '',
    providers: [TodoService],
    component: TodoListComponent,
    children: [
      {
        path: 'add',
        component: TodoFormComponent,
        data: { mode: 'create' }
      },
      {
        path: 'edit/:id',
        component: TodoFormComponent,
        data: { mode: 'update' }
      }
    ]
  }
];
EOF
)
    echo "$TODO_ROUTES_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/todo.routes.ts"
}

function create_todo_list_component() {
  local TODO_COMPONENTS_DIRECTORY=$1

      # Create template file
    local TODO_LIST_TEMPLATE=$(cat <<EOF
<div class="container mx-auto p-4">
  <h1 class="text-2xl font-bold mb-4">Todos</h1>

    <div class="mb-4">
        <button nz-button nzType="primary" (click)="addTodo()">Add Todo</button>
    </div>

  <!-- Todo List -->
  <nz-list [nzDataSource]="todos()" [nzRenderItem]="todoTemplate">
    <ng-template #todoTemplate let-todo>
      <nz-list-item>
        <div class="flex w-full items-center gap-2">
          <label nz-checkbox
            [ngModel]="todo.status === 'completed'"
            (ngModelChange)="toggleTodo(todo)"
          >
            <span [class.line-through]="todo.status === 'completed'">
              {{ todo.title }}
            </span>
          </label>
            <button nz-button nzType="text" (click)="editTodo(todo)">
                <span nz-icon nzType="edit"></span>
            </button>
          <button
            nz-button
            nzType="text"
            nzDanger
            class="ml-auto"
            (click)="deleteTodo(todo.id)"
          >
            <span nz-icon nzType="delete"></span>
          </button>
        </div>
      </nz-list-item>
    </ng-template>
  </nz-list>
    <router-outlet></router-outlet>
</div>
EOF
)
    echo "$TODO_LIST_TEMPLATE" > "$TODO_COMPONENTS_DIRECTORY/todo-list.component.html"
    # Create Todo List Component
    local TODO_LIST_COMPONENT_CONTENT=$(cat <<'EOF'
import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { NzButtonModule } from 'ng-zorro-antd/button';
import { NzInputModule } from 'ng-zorro-antd/input';
import { NzIconModule } from 'ng-zorro-antd/icon';
import { NzListModule } from 'ng-zorro-antd/list';
import { NzCheckboxModule } from 'ng-zorro-antd/checkbox';
import { TodoService } from './state/todo.service';
import { Todo } from './state/todo.model';
import { Router, RouterModule } from '@angular/router';
import { NzModalService, NzModalModule } from 'ng-zorro-antd/modal';
import { TodoModalComponent } from './todo-modal.component';

@Component({
  selector: 'todo-list',
  standalone: true,
    imports: [
        CommonModule,
        FormsModule,
        NzButtonModule,
        NzInputModule,
        NzIconModule,
        NzListModule,
        NzCheckboxModule,
        RouterModule,
        NzModalModule
    ],
  templateUrl: './todo-list.component.html'
})
export class TodoListComponent {
  private todoService = inject(TodoService);
  private router = inject(Router);
  private modalService = inject(NzModalService);
  todos = signal<Todo[]>([]);
  newTodoTitle = '';

  constructor() {
    this.loadTodos();
  }

  private loadTodos() {
    this.todoService.getTodos().subscribe(todos => this.todos.set(todos));
  }

    addTodo() {
        this.router.navigate(['todos', 'add']);
    }


  toggleTodo(todo: Todo) {
    const newStatus = todo.status === 'completed' ? 'pending' : 'completed';
    this.todoService.updateTodo(todo.id, { status: newStatus })
      .subscribe(() => this.loadTodos());
  }

  editTodo(todo: Todo) { // Pass the whole todo object
    this.modalService.create({
      nzTitle: 'Edit Todo',
      nzContent: TodoModalComponent,
      nzData: { todo: todo }, // Pass the todo data to the modal
      nzOnOk: (componentInstance: TodoModalComponent) => { // Handle the OK button
        return componentInstance.onSubmit();
      },
    });
  }

  deleteTodo(id: string) {
    this.todoService.deleteTodo(id)
      .subscribe(() => this.loadTodos());
  }
}
EOF
)

    echo "$TODO_LIST_COMPONENT_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/todo-list.component.ts"
}

function create_todo_form_component() {
    local TODO_COMPONENTS_DIRECTORY=$1

      # Create template file
    local TODO_FORM_TEMPLATE=$(cat <<EOF
<form [formGroup]="form" (ngSubmit)="onSubmit()" nz-form>
  <formly-form [form]="form" [fields]="fields" [model]="model"></formly-form>
    <div class="flex gap-2 justify-end">
      <button nz-button (click)="onCancel()">Cancel</button>
      <button nz-button nzType="primary" type="submit" [disabled]="!form.valid">Save</button>
    </div>
</form>

EOF
)
    echo "$TODO_FORM_TEMPLATE" > "$TODO_COMPONENTS_DIRECTORY/todo-form.component.html"

        local TODO_FORM_COMPONENT_CONTENT=$(cat <<'EOF'
import { Component, OnInit, inject } from '@angular/core';
import { FormGroup, ReactiveFormsModule } from '@angular/forms';
import { FormlyFieldConfig, FormlyModule } from '@ngx-formly/core';
import { NzFormModule } from 'ng-zorro-antd/form';
import { TodoService } from './state/todo.service';
import { ActivatedRoute, Router } from '@angular/router';
import { NzButtonModule } from 'ng-zorro-antd/button';
import { CommonModule } from '@angular/common';
import { todoFormlyFields } from './todo.formly';
import { Todo } from './state/todo.model';
import { firstValueFrom } from 'rxjs';

@Component({
  selector: 'todo-form',
  standalone: true,
  imports: [
    ReactiveFormsModule,
    FormlyModule,
    NzFormModule,
    NzButtonModule,
    CommonModule
  ],
  templateUrl: './todo-form.component.html'
})
export class TodoFormComponent implements OnInit {
  form = new FormGroup({});
  model: Partial<Todo> = {};
  fields: FormlyFieldConfig[] = todoFormlyFields;
  mode: 'create' | 'update' = 'create';

  private todoService = inject(TodoService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);

  ngOnInit() {
    this.route.data.subscribe(data => {
      this.mode = data['mode'];
      if (this.mode === 'update') {
        this.loadTodoForUpdate();
      }
    });
  }

  async loadTodoForUpdate() {
    const id = this.route.snapshot.paramMap.get('id');
    if (id) {
      const todo = await firstValueFrom(this.todoService.getTodoById(id));
      if (todo) {
        this.model = { ...todo, dueDate: new Date(todo.dueDate) };
      }
    }
  }


  async onSubmit() {
    if (this.form.valid) {
      try {
        if (this.mode === 'create') {
          const In1Year = new Date();
          In1Year.setFullYear(In1Year.getFullYear() + 1);
          const dueDate = this.model.dueDate || In1Year;

          await firstValueFrom(this.todoService.createTodo(
            {
              title: this.model.title || '',
              description: this.model.description || '',
              dueDate: dueDate,
              status: this.model.status || 'pending'
            }
          ));
        } else {
          await firstValueFrom(this.todoService.updateTodo(this.model.id!, this.model));
        }
        this.router.navigate(['/todos']);
      } catch (error) {
        console.error('Error saving todo:', error);
      }
    }
  }


  onCancel() {
    this.router.navigate(['/todos']);
  }
}
EOF
)
    echo "$TODO_FORM_COMPONENT_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/todo-form.component.ts"
}

function create_todo_formly_file() {
  local TODO_COMPONENTS_DIRECTORY=$1

  local TODO_FORMLY_CONTENT=$(cat <<'EOF'
import { FormlyFieldConfig } from '@ngx-formly/core';

export const todoFormlyFields: FormlyFieldConfig[] = [
  {
    key: 'title',
    type: 'input',
    props: {
      label: 'Title',
      placeholder: 'Enter title',
      required: true,
    },
  },
  {
    key: 'description',
    type: 'textarea',
    props: {
      label: 'Description',
      placeholder: 'Enter description',
    },
  },
  {
    key: 'dueDate',
    type: 'datepicker',
    props: {
      label: 'Due Date',
      placeholder: 'Select due date',
      required: false
    },
  },
    {
    key: 'status',
    type: 'select',
    defaultValue: 'pending',
    props: {
      label: 'Status',
      placeholder: 'Select Status',
      required: true,
        options: [
            { label: 'Pending', value: 'pending' },
            { label: 'Completed', value: 'completed' },
        ],
    },
  },
];

EOF
)

  echo "$TODO_FORMLY_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/todo.formly.ts"
}

function create_todo_setup() {
  local PROJECT_PATH=$1
  info "Creating Todo related files..."

  # Create Todo directory and its state subdirectory
  local TODO_COMPONENTS_DIRECTORY="$PROJECT_PATH/src/app/pages/todo"
  mkdir -p "$TODO_COMPONENTS_DIRECTORY/state"
  create_todo_model "$TODO_COMPONENTS_DIRECTORY"
  create_todo_service "$TODO_COMPONENTS_DIRECTORY"
  create_todo_routes "$TODO_COMPONENTS_DIRECTORY"
  create_todo_list_component "$TODO_COMPONENTS_DIRECTORY"
    create_todo_form_component "$TODO_COMPONENTS_DIRECTORY"
    create_todo_formly_file "$TODO_COMPONENTS_DIRECTORY"
}

function create_navigation_service() {
    local CORE_NAV_DIR=$1
      # Create navigation service
    local NAV_SERVICE_CONTENT=$(cat <<EOF
import { Injectable } from '@angular/core';
import { Route, Routes } from '@angular/router';

export interface NavItem {
  path: string;
  title: string;
  icon: string;
  children?: NavItem[];
}

@Injectable({
  providedIn: 'root'
})
export class NavigationService {
  private iconMap: { [key: string]: string } = {
    welcome: 'dashboard',
    todos: 'unordered-list',
  };

  generateNavItems(routes: Routes): NavItem[] {
    // .filter(route => !route.path?.includes('**')) Filter out wildcard routes
    return routes
      .filter(route => !route.path?.includes('**'))
      .map(route => this.createNavItem(route))
      .filter(item => item !== null) as NavItem[];
  }

  private createNavItem(route: Route): NavItem | null {
    if (!route.path) return null;

    if (route.data?.['hideInNav']) return null;

    const title = route.data?.['title'] || this.capitalizeFirstLetter(route.path);
    const icon = this.iconMap[route.path] || 'default';

    const navItem: NavItem = {
      path: route.path,
      title: title,
      icon: icon,
    };

    if (route.children) {
      const children = route.children
        .map(child => this.createNavItem(child))
        .filter(child => child !== null) as NavItem[];

      if (children.length) {
        navItem.children = children;
      }
    }

    return navItem;
  }

  private capitalizeFirstLetter(string: string): string {
    return string.charAt(0).toUpperCase() + string.slice(1);
  }
}
EOF
)
    echo "$NAV_SERVICE_CONTENT" > "$CORE_NAV_DIR/navigation.service.ts"
}

function create_app_component() {
    local PROJECT_PATH=$1
    local PROJECT_NAME_TITLE=$2

    local APP_COMPONENT_TEMPLATE=$(cat <<EOF
<nz-layout class="app-layout">
  <nz-sider
    class="menu-sidebar"
    nzCollapsible
    nzWidth="256px"
    nzBreakpoint="md"
    [(nzCollapsed)]="isCollapsed"
  >
    <div class="sidebar-logo">
      <a href="https://ng.ant.design/" target="_blank">
        <img src="https://ng.ant.design/assets/img/logo.svg" alt="logo">
        <h1>${PROJECT_NAME_TITLE}</h1>
      </a>
    </div>
    <ul nz-menu nzTheme="dark" nzMode="inline" [nzInlineCollapsed]="isCollapsed">
      <ng-container *ngFor="let item of navigationItems">
        <li nz-menu-item *ngIf="!item.children?.length" [routerLink]="[item.path]">
          <span nz-icon [nzType]="item.icon"></span>
          <span>{{item.title}}</span>
        </li>
        <li nz-submenu *ngIf="item.children?.length" [nzTitle]="item.title" [nzIcon]="item.icon">
          <ul>
            <li nz-menu-item *ngFor="let child of item.children" [routerLink]="[item.path, child.path]">
              {{child.title}}
            </li>
          </ul>
        </li>
      </ng-container>
    </ul>
  </nz-sider>
  <nz-layout>
    <nz-header>
      <div class="app-header">
        <span class="header-trigger" (click)="isCollapsed = !isCollapsed">
          <span nz-icon [nzType]="isCollapsed ? 'menu-unfold' : 'menu-fold'"></span>
        </span>
      </div>
    </nz-header>
    <nz-content>
      <div class="inner-content">
        <router-outlet></router-outlet>
      </div>
    </nz-content>
  </nz-layout>
</nz-layout>
EOF
)
    echo "$APP_COMPONENT_TEMPLATE" > "$PROJECT_PATH/src/app/app.component.html"

 # Update app.component.ts
    local APP_COMPONENT_CONTENT=$(cat <<EOF
import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { NzLayoutModule } from 'ng-zorro-antd/layout';
import { NzMenuModule } from 'ng-zorro-antd/menu';
import { NzIconModule } from 'ng-zorro-antd/icon';
import { NavigationService, NavItem } from './core/navigation/navigation.service';
import { routes } from './app.routes';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [
    CommonModule,
    RouterModule,
    NzLayoutModule,
    NzMenuModule,
    NzIconModule
  ],
  templateUrl: './app.component.html',
  styleUrl: './app.component.less'
})
export class AppComponent implements OnInit {
  isCollapsed = localStorage.getItem('isCollapsed') === 'true';
  navigationItems: NavItem[] = [];

  constructor(private navigationService: NavigationService) {}

  ngOnInit() {
    this.navigationItems = this.navigationService.generateNavItems(routes);
    this.updateIsCollapsed();
  }

    updateIsCollapsed() {
      localStorage.setItem('isCollapsed', this.isCollapsed.toString());
  }
}
EOF
)

    echo "$APP_COMPONENT_CONTENT" > "$PROJECT_PATH/src/app/app.component.ts"

}

function create_app_routes() {
    local PROJECT_PATH=$1
     # Update app.routes.ts
    local ROUTES_CONTENT=$(cat <<EOF
import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    path: '',
    pathMatch: 'full',
    redirectTo: 'welcome',
    data: { hideInNav: true }
  },
  {
    path: 'welcome',
    loadChildren: () => import('./pages/welcome/welcome.routes').then(m => m.WELCOME_ROUTES),
    data: {
      title: 'Welcome',
      icon: 'dashboard'
    }
  },
  {
    path: 'todos',
    loadChildren: () => import('./pages/todo/todo.routes').then(m => m.TODO_ROUTES),
    data: {
      title: 'Todo List',
      icon: 'unordered-list'
    }
  }
];
EOF
)
    echo "$ROUTES_CONTENT" > "$PROJECT_PATH/src/app/app.routes.ts"

}

function create_navigation_setup() {
  local PROJECT_PATH=$1
  local PROJECT_NAME_TITLE=$2
  info "Creating navigation files..."

  local CORE_NAV_DIR="$PROJECT_PATH/src/app/core/navigation"
  mkdir -p "$CORE_NAV_DIR"
    create_navigation_service "$CORE_NAV_DIR"
    create_app_component "$PROJECT_PATH" "$PROJECT_NAME_TITLE"
    create_app_routes "$PROJECT_PATH"

}

function setup_project_directories() {
    local UI_PATH="$1"
    local COMPONENTS_DIRECTORY="$UI_PATH/src/app/components"
    local TODO_COMPONENTS_DIRECTORY="$UI_PATH/src/app/pages/todo"

    info "Creating components directory: $COMPONENTS_DIRECTORY"
    mkdir -p "$COMPONENTS_DIRECTORY"
    if [ $? -ne 0 ]; then
        error "Failed to create components directory: $COMPONENTS_DIRECTORY"
        exit 1
    fi

    info "Creating formly-datepicker directory: $COMPONENTS_DIRECTORY/formly-datepicker"
    mkdir -p "$COMPONENTS_DIRECTORY/formly-datepicker"
    if [ $? -ne 0 ]; then
        error "Failed to create formly-datepicker directory: $COMPONENTS_DIRECTORY/formly-datepicker"
        exit 1
    fi

    info "Creating todo components directory: $TODO_COMPONENTS_DIRECTORY"
    mkdir -p "$TODO_COMPONENTS_DIRECTORY"
    if [ $? -ne 0 ]; then
        error "Failed to create todo components directory: $TODO_COMPONENTS_DIRECTORY"
        exit 1
    fi
}

function create_project_components() {
    local COMPONENTS_DIRECTORY="$1"
    local TODO_COMPONENTS_DIRECTORY="$2"

    create_formly_datepicker_component "$COMPONENTS_DIRECTORY"
    create_todo_modal_component "$TODO_COMPONENTS_DIRECTORY"
}

function configure_angular_project() {
    local UI_PATH="$1"
    local PROJECT_NAME_TITLE="$2"

    create_todo_setup "$UI_PATH"
    create_navigation_setup "$UI_PATH" "$PROJECT_NAME_TITLE"
}

function init() {
    local PROJECT_NAME=${1:-'hq-app'}
    read -e -p "Enter Your Project Folder Name:" -i "$PROJECT_NAME" PROJECT_NAME
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
    echo -e "node_modules\ndist/\n" > ".gitignore"

    create_dockerfile "$PROJECT_NAME/$UI_FOLDER_NAME"

    info "Creating fake JSON server ..."
    create_fake_json_server "$PROJECT_PATH"

    npm init -y
    npm install --save-exact --save-dev @angular/cli@latest
    popd >/dev/null

    info "creating '$UI_PATH' folder.\n"
    mkdir -p "$UI_PATH"
    pushd "$UI_PATH" >/dev/null

    save_exact
    npx ng new "$UI_FOLDER_NAME" --ssr=false --directory ./ --routing --style=less --minimal --skip-tests --skip-git --strict
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

    info "NG Zorro setup done. Adding ngx-formly"
    npx ng add @ngx-formly/schematics@latest --ui-theme=ng-zorro-antd --verbose --skip-confirmation

    npm install @ngx-formly/core @ngx-formly/ng-zorro-antd --verbose --skip-confirmation

    setup_project_directories "$UI_PATH"

    local COMPONENTS_DIRECTORY="$UI_PATH/src/app/components"
    local TODO_COMPONENTS_DIRECTORY="$UI_PATH/src/app/pages/todo"
    create_project_components "$COMPONENTS_DIRECTORY" "$TODO_COMPONENTS_DIRECTORY"

    configure_angular_project "$UI_PATH" "$PROJECT_NAME_TITLE"


    local ICONS_PROVIDER_FILE_CONTENT=$(cat <<'EOF'
import { IconDefinition } from '@ant-design/icons-angular';
import { NzIconModule,provideNzIcons } from 'ng-zorro-antd/icon';

import { MenuFoldOutline, MenuUnfoldOutline, FormOutline, DashboardOutline, UnorderedListOutline, DeleteOutline, PlusOutline, EditOutline } from '@ant-design/icons-angular/icons';

const icons: IconDefinition[] = [MenuFoldOutline, MenuUnfoldOutline, DashboardOutline, FormOutline, UnorderedListOutline, DeleteOutline, PlusOutline, EditOutline];

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

import { registerLocaleData } from '@angular/common';
import { provideNzI18n, en_US } from 'ng-zorro-antd/i18n';
import en from '@angular/common/locales/en';
registerLocaleData(en);

import { routes } from './app.routes';
import { iconsProvider } from './icons-provider';
import { AppConfigService } from "./app.config.service";
import {  FormlyModule } from '@ngx-formly/core';
import { FormlyNgZorroAntdModule } from '@ngx-formly/ng-zorro-antd';
import { importProvidersFrom } from '@angular/core';
import { NzDatePickerModule } from 'ng-zorro-antd/date-picker';
import { FormlyFieldNzDatepicker } from './components/formly-datepicker/formly-field-nz-datepicker.component';

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
  providers: [
    provideNzI18n(en_US),
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideRouter(routes),
    iconsProvider,
    provideAnimations(),
    provideHttpClient(),
    AppConfigService, {
      provide: APP_INITIALIZER,
      useFactory: initializeApp,
      multi: true,
      deps: [HttpClient, AppConfigService],
    },
    importProvidersFrom(
      FormlyModule.forRoot({
        validationMessages: [{ name: 'required', message: 'This field is required' }],
        types: [
          {
            name: 'datepicker',
            component: FormlyFieldNzDatepicker,
            wrappers: ['form-field'],
          },
        ],
      }),
      FormlyNgZorroAntdModule,
      NzDatePickerModule,
    )
  ],
};

EOF
)
    info "Creating app.config.ts file ..."
    echo "$APP_CONFIG_FILE_CONTENT" > src/app/app.config.ts

    local CONFIG_JSON_CONTENT=$(cat <<'EOF'
{
  "restApiEndpoint": "http://localhost:3000",
  "loginUrl": "http://localhost:3000/login",
  "logoutUrl": "http://localhost:3000/logout",
  "refreshUrl": "http://localhost:3000/refresh",
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
    #  sed -i '' -e "s/Ant Design Of Angular/$PROJECT_NAME_TITLE/ig" src/app/app.component.html

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

    info "Creating TODO components ..."
    create_todo_setup "$UI_PATH"

    info "Creating navigation setup ..."
    create_navigation_setup "$UI_PATH" "$PROJECT_NAME_TITLE"

    info "Creating styles.less file ..."
    echo "$STYLESS_DOT_LESS_FILE_CONTENT" > src/styles.less

    popd

    success "✔ All done. Starting ui server from the folder of '$PROJECT_NAME/$UI_FOLDER_NAME' ...\n"
    start "$CURRENT_DIRECTORY/$PROJECT_NAME/$UI_FOLDER_NAME"
}

function generate_page() {
 local PAGE_NAME=$1
 local PROJECT_PATH="$UI_PATH"
 # Generate the module and routing module with standalone flag
 npx ng g m "pages/$PAGE_NAME" --routing --route "$PAGE_NAME" --module app.module --standalone

 # Generate component inside pages/$PAGE_NAME
 npx ng g c "pages/$PAGE_NAME" --standalone --inline-template --skip-tests --inline-style
}

function help() {
 echo "Usage: $0 <command> [options]"
 echo "Commands:"
 echo "  init [project-name] [ui-folder-name]  Initialize a new Angular project"
 echo "  generate-page <page-name>              Generate a new page"
 echo "  start                                   Start the Angular app"
 echo "  destroy <project-name>                 Destroy the project"
 echo "  help                                  Show this help message"
}

function start() {
 # TODO: add an option to start it as docker or not.
 local DIRECTORY=$1
 local PROJECT_ROOT=$(dirname "$DIRECTORY")

 # Start JSON Server in background
 pushd "$PROJECT_ROOT/fake-json-server" >/dev/null
 npx json-server db.json &
 popd >/dev/null

 # Start Angular app
 pushd "$DIRECTORY" >/dev/null
 npx ng serve --verbose --open
 popd >/dev/null
}

function create_todo_modal_component() {
    local TODO_COMPONENTS_DIRECTORY=$1

      # Create template file
    local TODO_MODAL_TEMPLATE=$(cat <<EOF
<form [formGroup]="form" (ngSubmit)="onSubmit()" nz-form>
    <formly-form [form]="form" [fields]="fields" [model]="model"></formly-form>
    <div class="flex gap-2 justify-end">
        <button nz-button (click)="cancel()">Cancel</button>
        <button nz-button nzType="primary" type="submit" [disabled]="!form.valid">Save</button>
    </div>
</form>
EOF
)
    echo "$TODO_MODAL_TEMPLATE" > "$TODO_COMPONENTS_DIRECTORY/todo-modal.component.html"

        local TODO_MODAL_COMPONENT_CONTENT=$(cat <<'EOF'
import { Component, inject, OnInit } from '@angular/core';
import { FormGroup, ReactiveFormsModule } from '@angular/forms';
import { FormlyFieldConfig, FormlyModule } from '@ngx-formly/core';
import { NZ_MODAL_DATA, NzModalRef, NzModalModule } from 'ng-zorro-antd/modal';
import { NzFormModule } from 'ng-zorro-antd/form';
import { NzButtonModule } from 'ng-zorro-antd/button';
import { CommonModule } from '@angular/common';
import { todoFormlyFields } from './todo.formly';
import { Todo } from './state/todo.model';
import { TodoService } from './state/todo.service';
import { firstValueFrom } from 'rxjs';

@Component({
    selector: 'todo-modal',
    standalone: true,
    imports: [
        CommonModule,
        ReactiveFormsModule,
        FormlyModule,
        NzFormModule,
        NzButtonModule,
        NzModalModule
    ],
    templateUrl: './todo-modal.component.html'
})
export class TodoModalComponent implements OnInit {
    readonly data: { todo: Todo } = inject(NZ_MODAL_DATA);
    private modal: NzModalRef = inject(NzModalRef);
    private todoService = inject(TodoService);

    form = new FormGroup({});
    model: Partial<Todo> = {};
    fields: FormlyFieldConfig[] = todoFormlyFields;

    ngOnInit() {
        this.model = { ...this.data.todo, dueDate: new Date(this.data.todo.dueDate) };
    }

    async onSubmit() {
        if (this.form.valid) {
            try {
                await firstValueFrom(this.todoService.updateTodo(this.model.id!, this.model));
                this.modal.close();
            } catch (error) {
                console.error('Error saving todo:', error);
            }
        }
    }

    cancel() {
        this.modal.destroy();
    }
}
EOF
)
    echo "$TODO_MODAL_COMPONENT_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/todo-modal.component.ts"
}

function create_formly_datepicker_component() {
    local COMPONENTS_DIRECTORY=$1

    local FORMLY_DATEPICKER_COMPONENT_CONTENT=$(cat <<'EOF'
import { Component } from '@angular/core';
import { FieldType, FieldTypeConfig } from '@ngx-formly/core';
import { NzDatePickerModule } from 'ng-zorro-antd/date-picker';
import { ReactiveFormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';

interface DatePickerFieldProps {
  placeholder?: string;
  disabled?: boolean;
  nzFormat?: string;
}

type DatePickerFieldConfig = FieldTypeConfig<DatePickerFieldProps>;

@Component({
  selector: 'formly-field-nz-datepicker',
  standalone: true,
  imports: [NzDatePickerModule, ReactiveFormsModule, CommonModule],
  template: `
    <nz-date-picker
      [formControl]="formControl"
      [nzPlaceHolder]="field.props.placeholder || ''"
      [nzDisabled]="field.props.disabled || false"
      [nzFormat]="field.props.nzFormat || ''"
    >
    </nz-date-picker>
  `,
})
export class FormlyFieldNzDatepicker extends FieldType<DatePickerFieldConfig> {

}
EOF
)
    echo "$FORMLY_DATEPICKER_COMPONENT_CONTENT" > "$COMPONENTS_DIRECTORY/formly-datepicker/formly-field-nz-datepicker.component.ts"
}

function main() {
 local COMMAND=$1
 case $COMMAND in
 init)
   init "${@:2}"
   ;;
 generate-page)
   generate_page "${@:2}"
   ;;
 start)
   start "${@:2}"
   ;;
 destroy)
   destroy "${@:2}"
   ;;
 help)
   help
   ;;
 *)
   error "Unknown command: $COMMAND"
   help
   exit 1
   ;;
 esac
}

UI_PATH="$CURRENT_DIRECTORY/$PROJECT_NAME/$UI_FOLDER_NAME"

main "$@"
