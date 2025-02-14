#!/usr/bin/env bash
printf "Bash version: %s\n" "$BASH_VERSION"

export NG_CLI_ANALYTICS=false

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
  npm install --save-dev --save-exact json-server@0.17.4

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
    }
  ],
  "users": [
    { "id": "TEST_USER", "name": "Test User", "email": "test.user@example.com" }
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

  # Create server.js to add custom routes and token simulation
  local SERVER_JS_CONTENT=$(cat <<'EOF'
const jsonServer = require('json-server');
const server = jsonServer.create();
const router = jsonServer.router('db.json');
const middlewares = jsonServer.defaults();

server.use(middlewares);
server.use(jsonServer.bodyParser);

// Function to generate a dummy JWT (for simulation purposes only)
function generateDummyToken(type) {
  const payload = {
    iss: 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_USER_POOL_ID', // Replace with your issuer
    aud: 'YOUR_CLIENT_ID', // Replace with your client ID
    exp: Math.floor(Date.now() / 1000) + (60 * 60), // Token expires in 1 hour
    token_use: type,
    email: 'demo@example.com',
    name: 'Demo User'
    // Add other claims as needed for your simulation
  };
  const header = { alg: 'none' }; // No signature for dummy token
  const headerEncoded = Buffer.from(JSON.stringify(header)).toString('base64url').replace(/=+$/, '');
  const payloadEncoded = Buffer.from(JSON.stringify(payload)).toString('base64url').replace(/=+$/, '');
  return `${headerEncoded}.${payloadEncoded}.`; // No signature part for 'none' algorithm
}

function format_cookie_date(timestamp) {
    const date = new Date(timestamp * 1000); // Convert seconds to milliseconds
    return date.toUTCString();
}

function create_cookie_header(name, value, expiration) {
    let cookieString = `${name}=${value}`;
    cookieString += '; Secure';
    cookieString += '; HttpOnly';
    cookieString += '; SameSite=Lax';
    cookieString += '; Path=/';
    if (expiration) {
        cookieString += `; Expires=${format_cookie_date(expiration)}`;
    }
    return cookieString;
}

// Endpoint to simulate login and set cookies
server.get('/login', (req, res) => {
  const accessToken = generateDummyToken('access');
  const idToken = generateDummyToken('id');
  const refreshToken = 'DUMMY_REFRESH_TOKEN_VALUE';
  const nowSeconds = Math.floor(Date.now() / 1000);
  const OneMinuteInSeconds = 60;
  const FiveMinutesInSeconds = OneMinuteInSeconds * 5;
  const OneHourInSeconds = OneMinuteInSeconds * 60;
  const expirationSeconds = nowSeconds + OneHourInSeconds;

  const cookies = [
      create_cookie_header('id_token', idToken, expirationSeconds),
      create_cookie_header('access_token', accessToken, expirationSeconds),
      create_cookie_header('refresh_token', refreshToken, expirationSeconds) // Refresh token usually has longer expiry
  ];

  console.log('Simulated login - setting cookies');
  res.setHeader('Set-Cookie', cookies);
  res.redirect('http://localhost:4200'); // redirect to the ui page at localhost:4200
});

// Endpoint to simulate token refresh
server.post('/refresh-token', (req, res) => {
  const refreshToken = req.body.refresh_token; // Expect refresh_token in the request body

  if (!refreshToken) {
    return res.status(400).json({ error: 'refresh_token is required' });
  }

  // In a real scenario, you would validate the refresh_token and exchange it with Cognito
  // For this fake server, we just generate new dummy tokens
  const newAccessToken = generateDummyToken('access');
  const newIdToken = generateDummyToken('id');
  const newRefreshToken = 'DUMMY_NEW_REFRESH_TOKEN'; // In real scenario, generate or get new refresh token
  const nowSeconds = Math.floor(Date.now() / 1000);
  const expirationSeconds = nowSeconds + (60 * 60); // 1 hour expiration

  const cookies = [
        create_cookie_header('id_token', newIdToken, expirationSeconds),
        create_cookie_header('access_token', newAccessToken, expirationSeconds)
    ];


  console.log('Token refresh simulated - setting new access and id tokens cookies');
  res.setHeader('Set-Cookie', cookies);

  res.json({
    access_token: newAccessToken,
    id_token: newIdToken,
    refresh_token: newRefreshToken,
    expires_in: 3600 // 1 hour in seconds
  });
});

// Use default router
server.use(router);

const port = 3000; // or any port you prefer
server.listen(port, () => {
  console.log('JSON Server with custom routes is running on port ' + port);
});

EOF
)
  echo "$SERVER_JS_CONTENT" > server.js
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
  dueDate: Date | string;
  status: 'pending' | 'completed';
  createdAt: string;
  updatedAt: string;
  ttl?: number;
  editingTitle?: boolean;
  editingDescription?: boolean;
}

export type CreateTodoDto = Omit<Todo, 'id' | 'userId' | 'createdAt' | 'updatedAt' | 'ttl'>;
export type UpdateTodoDto = Partial<Todo>;
EOF
)
  echo "$TODO_MODEL_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/state/todo.model.ts"
}

function create_todo_service() {
  local TODO_COMPONENTS_DIRECTORY=$1
  local TODO_SERVICE_CONTENT=$(cat <<'EOF'
import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';
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
    return this.http.patch<Todo>(`${this.baseUrl}/${id}`, updates).pipe(
      tap(updatedTodo => {
        // Now service is also publishing the updated todo after successful update
        // so component can update in list and no need to recall list.
      })
    );
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
    local TODO_LIST_COMPONENT_CONTENT=$(cat <<'EOF'
import { Component, inject, signal, OnInit, OnDestroy, ElementRef, ViewChild } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { FormsModule, ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { NzButtonModule } from 'ng-zorro-antd/button';
import { NzInputModule } from 'ng-zorro-antd/input';
import { NzIconModule } from 'ng-zorro-antd/icon';
import { NzListModule } from 'ng-zorro-antd/list';
import { NzCheckboxModule } from 'ng-zorro-antd/checkbox';
import { TodoService } from './state/todo.service';
import { Todo, UpdateTodoDto } from './state/todo.model';
import { Router, RouterModule } from '@angular/router';
import { NzModalService, NzModalModule } from 'ng-zorro-antd/modal';
import { TodoModalComponent } from './todo-modal.component';
import { TodoCommunicationService } from '../../core/services/todo-communication.service'; // Import
import { Subscription } from 'rxjs'; // Import Subscription
import { NzTagModule } from 'ng-zorro-antd/tag'; // Import for the status tags
import { NzPopconfirmModule } from 'ng-zorro-antd/popconfirm';  // Import pop confirm module
import { NzDatePickerModule } from 'ng-zorro-antd/date-picker';
import { NzFormModule } from 'ng-zorro-antd/form';


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
        NzModalModule,
        NzTagModule,
        NzPopconfirmModule,
        DatePipe,
        ReactiveFormsModule,
        NzDatePickerModule,
        NzFormModule
    ],
  templateUrl: './todo-list.component.html',
  styleUrls: ['./todo-list.component.less'],
})
export class TodoListComponent implements OnInit, OnDestroy {
  private todoService = inject(TodoService);
  private router = inject(Router);
  private modalService = inject(NzModalService);
    private todoCommunicationService = inject(TodoCommunicationService);
   private fb = inject(FormBuilder);
  todos = signal<Todo[]>([]);
  newTodoTitle = '';
  private todoCreatedSubscription: Subscription | undefined;
  private todoUpdatedSubscription: Subscription | undefined;
  addTodoForm: FormGroup = this.fb.group({
    title: ['', Validators.required],
    description: [''],
    dueDate: [null] // Add dueDate control
  });

  constructor() {
  }

  ngOnInit() {
    this.loadTodos();
      this.todoCreatedSubscription = this.todoCommunicationService.todoCreated$.subscribe(todo => {
        this.addTodoToList(todo);
      });

      this.todoUpdatedSubscription = this.todoCommunicationService.todoUpdated$.subscribe(updatedTodo => {
           this.updateTodoInList(updatedTodo);
      });

    this.addTodoForm = this.fb.group({
      title: ['', Validators.required],
      description: [''],
      dueDate: [null] // Add dueDate control
    });
  }

  ngOnDestroy() {
    // Unsubscribe to prevent memory leaks
    this.todoCreatedSubscription?.unsubscribe();
    this.todoUpdatedSubscription?.unsubscribe();
  }

  private loadTodos() {
    this.todoService.getTodos().subscribe(todos => {
      todos.forEach(todo => {
        todo.dueDate = new Date(todo.dueDate);
        todo.editingTitle = false;
        todo.editingDescription = false;
      });
      this.todos.set(todos);
    });
  }

  submitNewTodo(): void {
    if (this.addTodoForm.valid) {
      const title = this.addTodoForm.get('title')?.value;
      const description = this.addTodoForm.get('description')?.value;
      const dueDate = this.addTodoForm.get('dueDate')?.value;

      this.todoService.createTodo({ title: title, description: description, dueDate: dueDate, status: 'pending' }).subscribe(
        (newTodo) => {
          this.todos.update(todos => [...todos, newTodo]);
          this.addTodoForm.reset();
        },
        (error) => {
          console.error('Error creating todo:', error);
        }
      );
    } else {
      console.log('Form is invalid');
    }
  }

  addTodo() {
    this.router.navigate(['todos', 'add']);
  }

  toggleTodo(todo: Todo) {
    const newStatus = todo.status === 'completed' ? 'pending' : 'completed';
    this.todoService.updateTodo(todo.id, { status: newStatus } as any)
    .subscribe(() => this.loadTodos());
  }

  confirmDelete(id: string): void {
    this.todoService.deleteTodo(id).subscribe(() => this.loadTodos());
  }

  cancelDelete(): void {
    console.log('Delete canceled');
  }


  editTodo(todo: Todo) {
    this.modalService.create({
      nzTitle: 'Edit Todo',
      nzContent: TodoModalComponent,
      nzData: { todo: todo },
      nzOnOk: (componentInstance: TodoModalComponent) => {
        return componentInstance.onSubmit();
      },
    });
  }

  addTodoToList(todo: Todo) {
        this.todos.update(todos => [...todos, todo]);
    }

  updateTodoInList(updatedTodo: Todo) {
        this.todos.update(todos => {
            return todos.map(todo => {
                if (todo.id === updatedTodo.id) {
                    return updatedTodo; // replace with updated todo
                }
                return todo; // otherwise return the original todo
            });
        });
    }

  trackByTodoId(_index: number, todo: Todo): string {
    return todo.id;
  }

  startEditTitle(todo: Todo) {
    todo.editingTitle = true;
    setTimeout(() => {
      const element = document.querySelector(`.todo-title[data-todo-id="${todo.id}"]`);
      if (element) {
        (element as HTMLElement).focus();
      }
    }, 0);
  }

  endEditTitle(todo: Todo) {
    todo.editingTitle = false;
    const element = document.querySelector(`.todo-title[data-todo-id="${todo.id}"]`) as HTMLElement;
    if (element) {
      const newTitle = element.innerText;
      if (newTitle !== todo.title) {
        this.updateTodo(todo, { title: newTitle });
      }
    }
  }

  startEditDescription(todo: Todo) {
    todo.editingDescription = true;
  }

  endEditDescription(todo: Todo) {
    todo.editingDescription = false;
    const element = document.querySelector(`.todo-description[data-todo-id="${todo.id}"]`) as HTMLElement;
    if (element) {
      const newDescription = element.innerText;
      if (newDescription !== todo.description) {
        this.updateTodo(todo, { description: newDescription });
      }
    }
  }

  private updateTodo(todo: Todo, updates: UpdateTodoDto) {
    this.todoService.updateTodo(todo.id, updates)
        .subscribe(updatedTodo => {
            this.todoCommunicationService.todoUpdated(updatedTodo); // Now publish updated todo itself
        });
  }
}
EOF
)
    echo "$TODO_LIST_COMPONENT_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/todo-list.component.ts"

    # Create template file - ADDED HERE
    local TODO_LIST_TEMPLATE_CONTENT=$(cat <<'EOF'
<div class="container">
  <div class="todo-header">
    <h1>My Todos</h1>
    <button nz-button nzType="primary" (click)="addTodo()">
      <span nz-icon nzType="plus" nzTheme="outline"></span> Add Todo
    </button>
  </div>

  <div class="todo-form">
    <h2>Add New Todo</h2>
    <form nz-form [formGroup]="addTodoForm" (ngSubmit)="submitNewTodo()">
      <nz-form-item>
        <nz-form-control>
          <input nz-input formControlName="title" placeholder="Title" />
        </nz-form-control>
      </nz-form-item>
      <nz-form-item>
        <nz-form-control>
          <textarea nz-input formControlName="description" rows="2" placeholder="Description"></textarea>
        </nz-form-control>
      </nz-form-item>
        <nz-form-item>
            <nz-form-control>
                <nz-date-picker formControlName="dueDate" nzPlaceHolder="Due Date"></nz-date-picker>
            </nz-form-control>
        </nz-form-item>
      <nz-form-item>
        <nz-form-control>
          <button nz-button nzType="primary" [disabled]="!addTodoForm.valid">Add Todo</button>
        </nz-form-control>
      </nz-form-item>
    </form>
  </div>
  <nz-list nzItemLayout="vertical">
    <nz-list-item *ngFor="let todo of todos(); trackBy: trackByTodoId" class="todo-item">
      <div nz-list-item-extra>
        <a nz-button nzType="primary" nzShape="circle" (click)="editTodo(todo)">
          <span nz-icon nzType="edit" nzTheme="outline"></span>
        </a>
        <nz-popconfirm
          nzTitle="Are you sure delete this task?"
          (nzOnConfirm)="confirmDelete(todo.id)"
          (nzOnCancel)="cancelDelete()"
        >
          <a nz-button nzType="primary" nzDanger nzShape="circle" nzPopconfirm>
            <span nz-icon nzType="delete" nzTheme="outline"></span>
          </a>
        </nz-popconfirm>
      </div>
      <div nz-list-item-content>
          <div class='todo-item-content' [class.todo-item-completed]="todo.status === 'completed'">
            <label nz-checkbox [ngModel]="todo.status === 'completed'" (ngModelChange)="toggleTodo(todo)"></label>
            <div class="todo-text-content" >
              <div class="todo-title-status">
                <span class="todo-title"
                      (click)="startEditTitle(todo)"
                      [contentEditable]="!!todo.editingTitle"
                      (blur)="endEditTitle(todo)"
                      (keydown.enter)="endEditTitle(todo)"
                      [attr.data-todo-id]="todo.id"
                     >{{ todo.title }}</span>
                 <nz-tag *ngIf="todo.status === 'completed'" nzColor="success">Completed</nz-tag>
                 <nz-tag *ngIf="todo.status === 'pending'" nzColor="warning">Pending</nz-tag>
               </div>
               <div class="todo-description-date">
                 <span class="todo-description"
                  (click)="startEditDescription(todo)"
                  [contentEditable]="!!todo.editingDescription"
                  (blur)="endEditDescription(todo)"
                  (keydown.enter)="endEditDescription(todo)"
                  [attr.data-todo-id]="todo.id"
                 >{{ todo.description }}</span>
                 <small class="todo-due-date">Due Date: {{ todo.dueDate | date }}</small>
               </div>
             </div>
          </div>
      </div>
    </nz-list-item>
  </nz-list>
</div>
EOF
)
    echo "$TODO_LIST_TEMPLATE_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/todo-list.component.html"
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
import { TodoCommunicationService } from '../../core/services/todo-communication.service'; // Import

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
  private todoCommunicationService = inject(TodoCommunicationService); // Import

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
        let newTodo: Todo;
        if (this.mode === 'create') {
            const In1Year = new Date();
            In1Year.setFullYear(In1Year.getFullYear() + 1);
            const dueDate = this.model.dueDate ? new Date(this.model.dueDate).toISOString() : In1Year.toISOString();

            // Await creation
             newTodo = await firstValueFrom(this.todoService.createTodo(
               {
                 title: this.model.title || '',
                 description: this.model.description || '',
                 dueDate: dueDate, // send as string to api
                 status: this.model.status || 'pending'
               }
             ));
          this.todoCommunicationService.todoCreated(newTodo); // after create todo created will update the ui.
        } else {
          newTodo = await firstValueFrom(this.todoService.updateTodo(this.model.id!, this.model));
          this.todoCommunicationService.todoUpdated(newTodo); // after create todo created will update the ui.
        }

         // After successful creation or update, navigate back
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
    profile: 'user' // Add profile icon
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
      <li nz-menu-item> <!-- Add Profile link here -->
          <a routerLink="/profile">
              <span nz-icon nzType="user"></span>
              <span>Profile</span>
          </a>
      </li>
       <li nz-menu-item>
           <a routerLink="/auth/logout">
               <span nz-icon nzType="logout"></span>
               <span>Logout</span>
           </a>
       </li>
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
  },
  {
    path: 'profile', // Add profile route
    loadChildren: () => import('./pages/profile/profile.routes').then(m => m.PROFILE_ROUTES),
    data: {
      title: 'Profile',
      icon: 'user'
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
    local PROFILE_COMPONENTS_DIRECTORY="$UI_PATH/src/app/pages/profile" # Add profile directory
    local CORE_SERVICE_DIRECTORY="$UI_PATH/src/app/core/services" # Add this line
    info "Creating components directory: $COMPONENTS_DIRECTORY"
    mkdir -p "$COMPONENTS_DIRECTORY"
    if [ $? -ne 0 ]; then
        error "Failed to create components directory: $COMPONENTS_DIRECTORY"
        exit 1
    fi

    info "Creating core services directory: $CORE_SERVICE_DIRECTORY" # Add this line
    mkdir -p "$CORE_SERVICE_DIRECTORY" # Add this line
    if [ $? -ne 0 ]; then # Add this line
        error "Failed to create components directory: $CORE_SERVICE_DIRECTORY" # Add this line
        exit 1 # Add this line
    fi # Add this line

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

    info "Creating profile components directory: $PROFILE_COMPONENTS_DIRECTORY" # Add profile directory creation
    mkdir -p "$PROFILE_COMPONENTS_DIRECTORY"
    if [ $? -ne 0 ]; then
        error "Failed to create profile components directory: $PROFILE_COMPONENTS_DIRECTORY"
        exit 1
    fi
}

function create_project_components() {
    local COMPONENTS_DIRECTORY="$1"
    local TODO_COMPONENTS_DIRECTORY="$2"
    local PROFILE_COMPONENTS_DIRECTORY="$3" # Add profile directory

    create_formly_datepicker_component "$COMPONENTS_DIRECTORY"
    create_todo_modal_component "$TODO_COMPONENTS_DIRECTORY"
    create_profile_component "$PROFILE_COMPONENTS_DIRECTORY" # Create profile component
}

function configure_angular_project() {
    local UI_PATH="$1"
    local PROJECT_NAME_TITLE=$2

    create_todo_setup "$UI_PATH"
    create_navigation_setup "$UI_PATH" "$PROJECT_NAME_TITLE"
    create_profile_setup "$UI_PATH" # Add profile setup
}
function create_todo_communication_service() { # Add this function
 local CORE_SERVICE_DIRECTORY=$1
 local TODO_COMMUNICATION_SERVICE_CONTENT=$(cat <<'EOF'
import { Injectable } from '@angular/core';
import { Subject } from 'rxjs';
import { Todo } from '../../pages/todo/state/todo.model';

@Injectable({
  providedIn: 'root'
})
export class TodoCommunicationService {
  private todoCreatedSource = new Subject<Todo>();
  todoCreated$ = this.todoCreatedSource.asObservable();

  private todoUpdatedSource = new Subject<Todo>();
  todoUpdated$ = this.todoUpdatedSource.asObservable();

    todoUpdated(todo: Todo) {
        this.todoUpdatedSource.next(todo);
    }

    todoCreated(todo: Todo) {
        this.todoCreatedSource.next(todo);
    }
}
EOF
)

  echo "$TODO_COMMUNICATION_SERVICE_CONTENT" > "$CORE_SERVICE_DIRECTORY/todo-communication.service.ts"
}
function create_todo_less_file() {
 local TODO_COMPONENTS_DIRECTORY=$1
 local TODO_LESS_CONTENT=$(cat <<'EOF'
.todo-item {
  display: flex;
  justify-content: space-between;
  align-items: flex-start; /* Align items to the start, especially checkbox and text */
  padding: 16px;
  border-bottom: 1px solid #f0f0f0;

  &:last-child {
    border-bottom: none;
  }

  .todo-form {
    margin-bottom: 20px;
    padding: 20px;
    border: 1px solid #e8e8e8;
    border-radius: 4px;
  }

  .todo-item-content {
    display: flex;
    align-items: flex-start; /* Align checkbox and text vertically */
    gap: 16px; /* Space between checkbox and text content */

    &.todo-item-completed {
      .todo-title, .todo-description {
        text-decoration: line-through;
        color: #777; /* Optional: make completed text a bit lighter */
      }
    }
  }

  .todo-text-content {
    display: flex;
    flex-direction: column; /* Stack title/status and description/date vertically */
    gap: 8px; /* Space between title/status and description/date */
  }

  .todo-title-status {
    display: flex;
    align-items: center; /* Align title and tags horizontally */
    gap: 10px; /* Space between title and tags */
  }

  .todo-description-date {
    display: flex;
    align-items: center; /* Align description and due date horizontally */
    gap: 20px; /* Space between description and due date */
    font-size: 0.9em;
    color: #777;
  }

  .todo-title {
    font-size: 1.2em;
    font-weight: 500;

    &:hover {
      cursor: text;
    }
  }

  .todo-description {
    // Style description if needed
    color: #777;
    font-size: 0.9em;

    &:hover {
      cursor: text;
    }
  }

  .todo-due-date {
    // Style due date if needed
  }

  nz-tag {
    margin-left: 8px;
  }
}
EOF
)

  echo "$TODO_LESS_CONTENT" > "$TODO_COMPONENTS_DIRECTORY/todo-list.component.less"
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
   local PROFILE_COMPONENTS_DIRECTORY="$UI_PATH/src/app/pages/profile" # Add profile directory
       local CORE_SERVICE_DIRECTORY="$UI_PATH/src/app/core/services"

   create_project_components "$COMPONENTS_DIRECTORY" "$TODO_COMPONENTS_DIRECTORY" "$PROFILE_COMPONENTS_DIRECTORY" # Pass profile dir

   configure_angular_project "$UI_PATH" "$PROJECT_NAME_TITLE"
       create_todo_communication_service "$CORE_SERVICE_DIRECTORY" # Add this line

   local ICONS_PROVIDER_FILE_CONTENT=$(cat <<'EOF'
import { IconDefinition } from '@ant-design/icons-angular';
import { NzIconModule,provideNzIcons } from 'ng-zorro-antd/icon';

import { MenuFoldOutline, MenuUnfoldOutline, FormOutline, DashboardOutline, UnorderedListOutline, DeleteOutline, PlusOutline, EditOutline, UserOutline, LogoutOutline } from '@ant-design/icons-angular/icons'; // Add UserOutline and LogoutOutline

const icons: IconDefinition[] = [MenuFoldOutline, MenuUnfoldOutline, FormOutline, DashboardOutline, UnorderedListOutline, DeleteOutline, PlusOutline, EditOutline, UserOutline, LogoutOutline]; // Add UserOutline and LogoutOutline

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
     "restApiEndpoint": "http://localhost:3000",
     "loginUrl": "http://localhost:3000/login",
     "logoutUrl": "http://localhost:3000/logout",
     "refreshUrl": "http://localhost:3000/refresh",
     "tokenUrl": "http://localhost:3000/token",
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
   provideZoneChangeDetection({ eventCoalescing: false }),
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

   # Add new todo style (replace with new template)
       info "creating new todo style..."
       create_todo_less_file "$TODO_COMPONENTS_DIRECTORY"
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

   info "Creating Profile components ..."
   create_profile_setup "$UI_PATH"

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
node server.js & # Run server.js instead of json-server directly
popd >/dev/null

# Start Angular app
pushd "$DIRECTORY" >/dev/null
npx ng serve --verbose --open
popd >/dev/null
}

function create_todo_modal_component() {
   local TODO_COMPONENTS_DIRECTORY=$1

     # Create template file
   local TODO_MODAL_TEMPLATE=$(cat <<'EOF'
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
import { TodoCommunicationService } from '../../core/services/todo-communication.service'; // Import

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
   private todoCommunicationService = inject(TodoCommunicationService);

   form = new FormGroup({});
   model: Partial<Todo> = {};
   fields: FormlyFieldConfig[] = todoFormlyFields;

   ngOnInit() {
       this.model = { ...this.data.todo, dueDate: new Date(this.data.todo.dueDate) };
   }

   async onSubmit() {
       if (this.form.valid) {
           try {
               const updatedTodo = await firstValueFrom(this.todoService.updateTodo(this.model.id!, this.model));
                this.todoCommunicationService.todoUpdated(updatedTodo);
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

function create_profile_setup() {
  local PROJECT_PATH=$1
  info "Creating Profile related files..."

  # Create Profile directory and its state subdirectory - ADD state directory here
  local PROFILE_COMPONENTS_DIRECTORY="$PROJECT_PATH/src/app/pages/profile"
  mkdir -p "$PROFILE_COMPONENTS_DIRECTORY/state" # Create the state subdirectory

  create_profile_component "$PROFILE_COMPONENTS_DIRECTORY"
  create_profile_routes "$PROFILE_COMPONENTS_DIRECTORY"
  create_profile_service "$PROFILE_COMPONENTS_DIRECTORY/state" # Pass state directory path
  create_profile_model "$PROFILE_COMPONENTS_DIRECTORY/state"   # Pass state directory path
}

function create_profile_component() {
    local PROFILE_COMPONENTS_DIRECTORY=$1
    local PROFILE_COMPONENT_CONTENT=$(cat <<'EOF'
import { Component, OnInit, inject, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ProfileService } from './state/profile.service';
import { Profile } from './state/profile.model';
import { NzCardModule } from 'ng-zorro-antd/card';
import { NzAvatarModule } from 'ng-zorro-antd/avatar';
import { NzButtonModule } from 'ng-zorro-antd/button';
import { NzModalService, NzModalModule } from 'ng-zorro-antd/modal';
import { interval, Subscription } from 'rxjs';
import { takeWhile } from 'rxjs/operators';

@Component({
  selector: 'app-profile',
  standalone: true,
  imports: [
    CommonModule,
    NzCardModule,
    NzAvatarModule,
    NzButtonModule,
    NzModalModule
  ],
  templateUrl: './profile.component.html',
  styleUrl: './profile.component.less'
})
export class ProfileComponent implements OnInit, OnDestroy {
  private profileService = inject(ProfileService);
  private modalService = inject(NzModalService);
  profile: Profile | null = null;
  sessionExpiry = 3600; // Example session expiry in seconds (1 hour)
  expiryTimer: Subscription | undefined;
  remainingTime: number = this.sessionExpiry;
  showRefreshPopup = false;

  ngOnInit(): void {
    this.loadProfile();
    this.startExpiryTimer();
  }

  ngOnDestroy(): void {
    this.stopExpiryTimer();
  }

  loadProfile(): void {
    this.profileService.getProfile().subscribe(data => {
      this.profile = data;
    });
  }

  startExpiryTimer(): void {
    this.expiryTimer = interval(1000)
      .pipe(takeWhile(() => this.remainingTime > 0 && !this.showRefreshPopup))
      .subscribe(() => {
        this.remainingTime--;
        if (this.remainingTime <= 60 && !this.showRefreshPopup) {
          this.showRefreshConfirmation();
        }
      });
  }

  stopExpiryTimer(): void {
    if (this.expiryTimer && !this.expiryTimer.closed) {
      this.expiryTimer.unsubscribe();
    }
  }

  showRefreshConfirmation(): void {
      this.showRefreshPopup = true;
      this.stopExpiryTimer(); // Pause the main timer

      this.modalService.confirm({
        nzTitle: 'Session Expiring Soon',
        nzContent: `<p>Your session is about to expire in <strong id="countdown">{{ remainingTimeForModal }}</strong> seconds. Do you want to extend your session?</p>`,
        nzOkText: 'Refresh Session',
        nzCancelText: 'Logout',
        nzOnOk: () => {
          this.refreshSession();
        },
        nzOnCancel: () => {
          // Redirect to logout or handle logout logic
          console.log('Logout action needed here');
          this.showRefreshPopup = false; // Ensure popup flag is reset
        },
        nzAfterOpen: () => {
          // Countdown inside the modal
          let modalCountdown = 60;
          const modalInterval = interval(1000).pipe(takeWhile(() => modalCountdown >= 0)).subscribe(count => {
            modalCountdown--;
            this.remainingTimeForModal = modalCountdown; // Update bindable property
            if (document.getElementById('countdown')) {
              document.getElementById('countdown')!.textContent = String(modalCountdown >= 0 ? modalCountdown : 0);
            }
            if (modalCountdown < 0) {
              modalInterval.unsubscribe();
              this.modalService.closeAll(); // Automatically close modal after countdown
              console.log('Session expired due to no refresh.');
              this.showRefreshPopup = false; // Ensure popup flag is reset
              // Handle automatic logout or session expiry action here
            }
          });
          this.modalCountdownSubscription = modalInterval; // Store for potential cleanup
        },
        nzAfterClose: () => {
          this.showRefreshPopup = false; // Reset popup flag when modal is closed
          this.startExpiryTimer(); // Restart main timer after modal is closed (regardless of action)
          if (this.modalCountdownSubscription && !this.modalCountdownSubscription.closed) {
            this.modalCountdownSubscription.unsubscribe(); // Cleanup modal countdown if it's still running
          }
        }
      } as any);
  }

  remainingTimeForModal: number = 60; // Bindable property for modal countdown
  private modalCountdownSubscription: Subscription | undefined;

  refreshSession(): void {
    this.profileService.refreshToken().subscribe(
      response => {
        console.log('Session refreshed successfully', response);
        this.remainingTime = this.sessionExpiry; // Reset main timer
        this.startExpiryTimer();
        this.showRefreshPopup = false; // Reset popup flag
        this.modalService.closeAll(); // Close the confirmation modal if it's still open  In a real app, you would update tokens in cookies or storage here.
      },
      error => {
        console.error('Failed to refresh session', error);
        this.showRefreshPopup = false; // Reset popup flag
        this.modalService.closeAll(); // Close the confirmation modal
        // Handle refresh failure (e.g., redirect to login)
      }
    );
  }
}
EOF
)
    echo "$PROFILE_COMPONENT_CONTENT" > "$PROFILE_COMPONENTS_DIRECTORY/profile.component.ts"

    local PROFILE_COMPONENT_TEMPLATE=$(cat <<'EOF'
<nz-card nzTitle="User Profile" *ngIf="profile">
  <nz-card-meta
          nzTitle="{{ profile.name }}"
          nzDescription="{{ profile.email }}">
    <nz-avatar nzIcon="user" nzSrc="{{ profile.avatar }}"></nz-avatar>
  </nz-card-meta>
  <ng-template nz-card-actions>
    <button nz-button nzType="primary" (click)="refreshSession()">Refresh Session</button>
  </ng-template>
</nz-card>
EOF
)
    echo "$PROFILE_COMPONENT_TEMPLATE" > "$PROFILE_COMPONENTS_DIRECTORY/profile.component.html"

    local PROFILE_COMPONENT_LESS=$(cat <<'EOF'
/* Add custom styles for profile component here if needed */
EOF
)
    echo "$PROFILE_COMPONENT_LESS" > "$PROFILE_COMPONENTS_DIRECTORY/profile.component.less"
}

function create_profile_routes() {
    local PROFILE_COMPONENTS_DIRECTORY=$1

    # Create Profile routes
    local PROFILE_ROUTES_CONTENT=$(cat <<'EOF'
import { Routes } from '@angular/router';
import { ProfileComponent } from './profile.component';
import { ProfileService } from './state/profile.service';

export const PROFILE_ROUTES: Routes = [
  {
    path: '',
    component: ProfileComponent,
    providers: [ProfileService]
  }
];
EOF
)
    echo "$PROFILE_ROUTES_CONTENT" > "$PROFILE_COMPONENTS_DIRECTORY/profile.routes.ts"
}

function create_profile_service() {
  local PROFILE_COMPONENTS_DIRECTORY=$1 # Parameter is path to 'state' directory
  local PROFILE_SERVICE_CONTENT=$(cat <<'EOF'
import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Profile } from './profile.model';
import { AppConfigService } from '../../../app.config.service';

@Injectable({
  providedIn: 'root'
})
export class ProfileService {
  private http = inject(HttpClient);
  private config = inject(AppConfigService);
  private baseUrl = `${this.config.getConfig().restApiEndpoint}`; // Assuming profile endpoint is at root API URL

  getProfile(): Observable<Profile> {
    return this.http.get<Profile>(`${this.baseUrl}/profile`); // Adjust endpoint if needed
  }

  refreshToken(): Observable<any> {
    return this.http.post<any>(`${this.baseUrl}/refresh-token`, { // Adjust endpoint if needed
      refresh_token: 'DUMMY_REFRESH_TOKEN' // In real app, get from storage
    });
  }
}
EOF
)
  echo "$PROFILE_SERVICE_CONTENT" > "$PROFILE_COMPONENTS_DIRECTORY/profile.service.ts" # Corrected path - no extra /state
}

function create_profile_model() {
  local PROFILE_COMPONENTS_DIRECTORY=$1 # Parameter is path to 'state' directory
  local PROFILE_MODEL_CONTENT=$(cat <<'EOF'
export interface Profile {
  name: string;
  email: string;
  avatar: string;
  // Add other profile properties as needed
}
EOF
)
  echo "$PROFILE_MODEL_CONTENT" > "$PROFILE_COMPONENTS_DIRECTORY/profile.model.ts" # Corrected path - no extra /state
}

UI_PATH="$CURRENT_DIRECTORY/$PROJECT_NAME/$UI_FOLDER_NAME"

main "$@"
