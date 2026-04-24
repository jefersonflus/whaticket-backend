#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-whaticket}"
APP_USER="${APP_USER:-whaticket}"
INSTALL_DIR="${INSTALL_DIR:-/opt/whaticket}"
BACKEND_DIR="$INSTALL_DIR/backend"
FRONTEND_DIR="$INSTALL_DIR/frontend"

BACKEND_REPO_URL="${BACKEND_REPO_URL:-https://github.com/jefersonflus/whaticket-backend.git}"
FRONTEND_REPO_URL="${FRONTEND_REPO_URL:-https://github.com/jefersonflus/whaticket-frontend.git}"
SOURCE_ZIP="${SOURCE_ZIP:-}"
BACKEND_ZIP="${BACKEND_ZIP:-}"
FRONTEND_ZIP="${FRONTEND_ZIP:-}"

NODE_VERSION="${NODE_VERSION:-24.14.0}"
DB_DIALECT="${DB_DIALECT:-mysql}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-whaticket}"
DB_USER="${DB_USER:-whaticket}"
DB_PASSWORD="${DB_PASSWORD:-}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"

BACKEND_PORT="${BACKEND_PORT:-4000}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
FRONTEND_DOMAIN="${FRONTEND_DOMAIN:-}"
BACKEND_DOMAIN="${BACKEND_DOMAIN:-}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
ENABLE_SSL="${ENABLE_SSL:-false}"
CONFIGURE_NGINX="${CONFIGURE_NGINX:-auto}"
FORCE_ENV="${FORCE_ENV:-false}"
SEED_DATABASE="${SEED_DATABASE:-true}"

ADMIN_EMAIL="${ADMIN_EMAIL:-admin@admin.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

BACKEND_PM2_NAME="${BACKEND_PM2_NAME:-$APP_NAME-backend}"
FRONTEND_PM2_NAME="${FRONTEND_PM2_NAME:-$APP_NAME-frontend}"

log() {
  printf '\n[whaticket] %s\n' "$*"
}

die() {
  printf '\n[whaticket] ERRO: %s\n' "$*" >&2
  exit 1
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

random_base64() {
  openssl rand -base64 32 | tr -d '\n'
}

random_password() {
  openssl rand -hex 16
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

validate_identifier() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[A-Za-z0-9_]+$ ]] || die "$name deve conter apenas letras, numeros e underscore."
}

run_as_app() {
  local command="$1"
  su -s /bin/bash -c "export NVM_DIR=\"\$HOME/.nvm\"; if [ -s \"\$NVM_DIR/nvm.sh\" ]; then . \"\$NVM_DIR/nvm.sh\"; fi; $command" "$APP_USER"
}

setup_git_auth() {
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    return 0
  fi

  GIT_ASKPASS_FILE="$(mktemp)"
  cat > "$GIT_ASKPASS_FILE" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *Password*) printf '%s\n' "${GITHUB_TOKEN:-}" ;;
  *) printf '\n' ;;
esac
ASKPASS
  chmod 700 "$GIT_ASKPASS_FILE"
  export GIT_ASKPASS="$GIT_ASKPASS_FILE"
  export GIT_TERMINAL_PROMPT=0
}

cleanup() {
  if [[ -n "${GIT_ASKPASS_FILE:-}" && -f "$GIT_ASKPASS_FILE" ]]; then
    rm -f "$GIT_ASKPASS_FILE"
  fi
}
trap cleanup EXIT

install_os_packages() {
  log "Instalando pacotes do sistema"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl git unzip rsync build-essential \
    mysql-server redis-server nginx ffmpeg openssl

  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    libnss3 libatk-bridge2.0-0 libgtk-3-0 libxss1 || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y libasound2 || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y libasound2t64 || true

  systemctl enable --now mysql || true
  systemctl enable --now redis-server || true
  systemctl enable --now nginx || true
}

ensure_user_and_dirs() {
  log "Preparando usuario e diretorios"
  if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$APP_USER"
  fi

  mkdir -p "$INSTALL_DIR" "$BACKEND_DIR" "$FRONTEND_DIR"
  chown -R "$APP_USER:$APP_USER" "$INSTALL_DIR"
}

install_node() {
  log "Instalando Node $NODE_VERSION com nvm"
  if [[ ! -s "/home/$APP_USER/.nvm/nvm.sh" ]]; then
    run_as_app "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE=/dev/null bash"
  fi

  run_as_app "nvm install '$NODE_VERSION' && nvm alias default '$NODE_VERSION' && nvm use '$NODE_VERSION' && npm install -g pm2"
}

copy_from_dir() {
  local source_dir="$1"
  local target_dir="$2"
  rsync -a --delete --exclude='.git' --exclude='node_modules' --exclude='dist' --exclude='build' "$source_dir/" "$target_dir/"
}

extract_monorepo_zip() {
  local zip_path="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  unzip -q "$zip_path" -d "$tmp_dir"

  local backend_src frontend_src
  backend_src="$(find "$tmp_dir" -type f -path '*/backend/package.json' -printf '%h\n' | head -n 1)"
  frontend_src="$(find "$tmp_dir" -type f -path '*/frontend/package.json' -printf '%h\n' | head -n 1)"

  [[ -n "$backend_src" ]] || die "Nao encontrei backend/package.json dentro de $zip_path."
  [[ -n "$frontend_src" ]] || die "Nao encontrei frontend/package.json dentro de $zip_path."

  copy_from_dir "$backend_src" "$BACKEND_DIR"
  copy_from_dir "$frontend_src" "$FRONTEND_DIR"
  rm -rf "$tmp_dir"
}

extract_single_zip() {
  local zip_path="$1"
  local target_dir="$2"
  local label="$3"
  local tmp_dir source_dir
  tmp_dir="$(mktemp -d)"
  unzip -q "$zip_path" -d "$tmp_dir"
  source_dir="$(find "$tmp_dir" -maxdepth 4 -type f -name package.json -printf '%h\n' | head -n 1)"
  [[ -n "$source_dir" ]] || die "Nao encontrei package.json no zip do $label."
  copy_from_dir "$source_dir" "$target_dir"
  rm -rf "$tmp_dir"
}

fetch_git_repo() {
  local repo_url="$1"
  local target_dir="$2"
  local label="$3"

  if [[ -d "$target_dir/.git" ]]; then
    log "Atualizando $label"
    git -C "$target_dir" pull --ff-only
  else
    log "Baixando $label"
    rm -rf "$target_dir"
    git clone "$repo_url" "$target_dir"
  fi

  chown -R "$APP_USER:$APP_USER" "$target_dir"
}

fetch_sources() {
  setup_git_auth

  if [[ -n "$SOURCE_ZIP" ]]; then
    log "Extraindo zip unico: $SOURCE_ZIP"
    extract_monorepo_zip "$SOURCE_ZIP"
  else
    if [[ -n "$BACKEND_ZIP" ]]; then
      log "Extraindo backend: $BACKEND_ZIP"
      extract_single_zip "$BACKEND_ZIP" "$BACKEND_DIR" "backend"
    else
      fetch_git_repo "$BACKEND_REPO_URL" "$BACKEND_DIR" "backend"
    fi

    if [[ -n "$FRONTEND_ZIP" ]]; then
      log "Extraindo frontend: $FRONTEND_ZIP"
      extract_single_zip "$FRONTEND_ZIP" "$FRONTEND_DIR" "frontend"
    else
      fetch_git_repo "$FRONTEND_REPO_URL" "$FRONTEND_DIR" "frontend"
    fi
  fi

  mkdir -p "$BACKEND_DIR/public/certs" "$BACKEND_DIR/public/temp"
  chown -R "$APP_USER:$APP_USER" "$INSTALL_DIR"
}

create_database() {
  [[ "$DB_DIALECT" == "mysql" ]] || die "Este instalador automatiza apenas MySQL."
  validate_identifier "DB_NAME" "$DB_NAME"
  validate_identifier "DB_USER" "$DB_USER"

  if [[ "$DB_HOST" != "localhost" && "$DB_HOST" != "127.0.0.1" ]]; then
    log "DB_HOST externo detectado; pulando criacao automatica do banco."
    return 0
  fi

  log "Criando banco e usuario MySQL"
  local db_pass_escaped
  db_pass_escaped="$(sql_escape "$DB_PASSWORD")"

  local mysql_cmd=(mysql -uroot)
  if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
    mysql_cmd+=("-p$MYSQL_ROOT_PASSWORD")
  fi

  "${mysql_cmd[@]}" <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$db_pass_escaped';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$db_pass_escaped';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL
}

derive_urls() {
  if [[ -n "$FRONTEND_DOMAIN" ]]; then
    FRONTEND_PUBLIC_URL="${FRONTEND_PUBLIC_URL:-https://$FRONTEND_DOMAIN}"
  else
    FRONTEND_PUBLIC_URL="${FRONTEND_PUBLIC_URL:-http://localhost:$FRONTEND_PORT}"
  fi

  if [[ -n "$BACKEND_DOMAIN" ]]; then
    BACKEND_PUBLIC_URL="${BACKEND_PUBLIC_URL:-https://$BACKEND_DOMAIN}"
  else
    BACKEND_PUBLIC_URL="${BACKEND_PUBLIC_URL:-http://localhost:$BACKEND_PORT}"
  fi
}

write_env_files() {
  log "Gerando arquivos .env"
  DB_PASSWORD="${DB_PASSWORD:-$(random_password)}"
  ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(random_password)}"
  JWT_SECRET="${JWT_SECRET:-$(random_base64)}"
  JWT_REFRESH_SECRET="${JWT_REFRESH_SECRET:-$(random_base64)}"
  derive_urls

  if [[ ! -f "$BACKEND_DIR/.env" || "$FORCE_ENV" == "true" ]]; then
    cat > "$BACKEND_DIR/.env" <<EOF
NODE_ENV=production
BACKEND_URL=$BACKEND_PUBLIC_URL
FRONTEND_URL=$FRONTEND_PUBLIC_URL
PROXY_PORT=
PORT=$BACKEND_PORT

DB_DIALECT=$DB_DIALECT
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_USER=$DB_USER
DB_PASS=$DB_PASSWORD
DB_NAME=$DB_NAME

JWT_SECRET=$JWT_SECRET
JWT_REFRESH_SECRET=$JWT_REFRESH_SECRET

REDIS_URI=redis://127.0.0.1:6379
REDIS_OPT_LIMITER_MAX=1
REDIS_OPT_LIMITER_DURATION=3000

USER_LIMIT=10000
CONNECTIONS_LIMIT=100000
CLOSED_SEND_BY_ME=true

GERENCIANET_SANDBOX=false
GERENCIANET_CLIENT_ID=
GERENCIANET_CLIENT_SECRET=
GERENCIANET_PIX_CERT=
GERENCIANET_PIX_KEY=

CONTACT_LIST_IMPORT_ALLOW_XLSX=true
CONTACT_LIST_IMPORT_MAX_SIZE_MB=5
CONTACT_LIST_IMPORT_MAX_ROWS=10000
CONTACT_LIST_IMPORT_XLSX_TIMEOUT_MS=15000
EOF
  else
    log "Mantendo $BACKEND_DIR/.env existente"
  fi

  if [[ ! -f "$FRONTEND_DIR/.env" || "$FORCE_ENV" == "true" ]]; then
    cat > "$FRONTEND_DIR/.env" <<EOF
REACT_APP_BACKEND_URL=$BACKEND_PUBLIC_URL
REACT_APP_HOURS_CLOSE_TICKETS_AUTO=24
REACT_APP_FACEBOOK_APP_ID=
REACT_APP_NAME_SYSTEM=Whaticket
REACT_APP_NUMBER_SUPPORT=
NODE_ENV=production
EOF
  else
    log "Mantendo $FRONTEND_DIR/.env existente"
  fi

  cat > "$INSTALL_DIR/install-secrets.env" <<EOF
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASSWORD=$ADMIN_PASSWORD
BACKEND_URL=$BACKEND_PUBLIC_URL
FRONTEND_URL=$FRONTEND_PUBLIC_URL
EOF
  chmod 600 "$INSTALL_DIR/install-secrets.env"
  chown -R "$APP_USER:$APP_USER" "$INSTALL_DIR"
}

npm_install() {
  local dir="$1"
  run_as_app "cd '$dir' && nvm use '$NODE_VERSION' >/dev/null && if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then npm ci || npm install; else npm install; fi"
}

build_and_migrate() {
  log "Instalando dependencias do backend"
  npm_install "$BACKEND_DIR"

  log "Compilando backend"
  run_as_app "cd '$BACKEND_DIR' && nvm use '$NODE_VERSION' >/dev/null && npm run build"

  log "Executando migrations"
  run_as_app "cd '$BACKEND_DIR' && nvm use '$NODE_VERSION' >/dev/null && npx sequelize db:migrate"

  if [[ "$SEED_DATABASE" == "true" ]]; then
    log "Executando seeds iniciais"
    run_as_app "cd '$BACKEND_DIR' && nvm use '$NODE_VERSION' >/dev/null && SEED_ADMIN_EMAIL='$ADMIN_EMAIL' SEED_ADMIN_PASSWORD='$ADMIN_PASSWORD' npx sequelize db:seed:all"
  fi

  log "Instalando dependencias do frontend"
  npm_install "$FRONTEND_DIR"

  log "Compilando frontend"
  run_as_app "cd '$FRONTEND_DIR' && nvm use '$NODE_VERSION' >/dev/null && npm run build"
}

start_pm2() {
  log "Subindo processos no PM2"
  run_as_app "cd '$BACKEND_DIR' && nvm use '$NODE_VERSION' >/dev/null && pm2 delete '$BACKEND_PM2_NAME' >/dev/null 2>&1 || true"
  run_as_app "cd '$FRONTEND_DIR' && nvm use '$NODE_VERSION' >/dev/null && pm2 delete '$FRONTEND_PM2_NAME' >/dev/null 2>&1 || true"

  run_as_app "cd '$BACKEND_DIR' && nvm use '$NODE_VERSION' >/dev/null && PORT='$BACKEND_PORT' pm2 start dist/server.js --name '$BACKEND_PM2_NAME' --update-env"
  run_as_app "cd '$FRONTEND_DIR' && nvm use '$NODE_VERSION' >/dev/null && PORT='$FRONTEND_PORT' pm2 start server.js --name '$FRONTEND_PM2_NAME' --update-env"
  run_as_app "pm2 save"

  local pm2_bin
  pm2_bin="$(su -s /bin/bash -c "export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\"; command -v pm2" "$APP_USER")"
  env PATH="$(dirname "$pm2_bin"):$PATH" "$pm2_bin" startup systemd -u "$APP_USER" --hp "/home/$APP_USER" || true
}

configure_nginx() {
  if [[ "$CONFIGURE_NGINX" == "auto" ]]; then
    if [[ -n "$FRONTEND_DOMAIN" && -n "$BACKEND_DOMAIN" ]]; then
      CONFIGURE_NGINX=true
    else
      CONFIGURE_NGINX=false
    fi
  fi

  [[ "$CONFIGURE_NGINX" == "true" ]] || return 0
  [[ -n "$FRONTEND_DOMAIN" && -n "$BACKEND_DOMAIN" ]] || die "Para Nginx informe FRONTEND_DOMAIN e BACKEND_DOMAIN."
  [[ "$FRONTEND_DOMAIN" != "$BACKEND_DOMAIN" ]] || die "FRONTEND_DOMAIN e BACKEND_DOMAIN devem ser diferentes."

  log "Configurando Nginx"
  cat > /etc/nginx/sites-available/whaticket.conf <<EOF
server {
  listen 80;
  server_name $FRONTEND_DOMAIN;

  location / {
    proxy_pass http://127.0.0.1:$FRONTEND_PORT;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}

server {
  listen 80;
  server_name $BACKEND_DOMAIN;
  client_max_body_size 100M;

  location / {
    proxy_pass http://127.0.0.1:$BACKEND_PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

  ln -sf /etc/nginx/sites-available/whaticket.conf /etc/nginx/sites-enabled/whaticket.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl reload nginx

  if [[ "$ENABLE_SSL" == "true" ]]; then
    [[ -n "$CERTBOT_EMAIL" ]] || die "Para SSL informe CERTBOT_EMAIL."
    log "Emitindo certificados SSL"
    DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-nginx
    certbot --nginx --non-interactive --agree-tos -m "$CERTBOT_EMAIL" -d "$FRONTEND_DOMAIN" -d "$BACKEND_DOMAIN"
  fi
}

main() {
  DB_PASSWORD="${DB_PASSWORD:-$(random_password)}"
  ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(random_password)}"

  install_os_packages
  ensure_user_and_dirs
  install_node
  fetch_sources
  create_database
  write_env_files
  build_and_migrate
  start_pm2
  configure_nginx

  log "Instalacao concluida"
  printf 'Frontend: %s\n' "$FRONTEND_PUBLIC_URL"
  printf 'Backend:  %s\n' "$BACKEND_PUBLIC_URL"
  printf 'Credenciais e segredos: %s\n' "$INSTALL_DIR/install-secrets.env"
  printf 'Admin: %s\n' "$ADMIN_EMAIL"
}

main "$@"
