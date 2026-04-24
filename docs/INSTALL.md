# Instalacao do Whaticket

Este guia instala frontend e backend em uma VPS Ubuntu usando MySQL, Redis, Node via nvm, PM2 e, opcionalmente, Nginx/SSL.

## Requisitos

- Ubuntu 20.04, 22.04 ou 24.04.
- Acesso root ou usuario com sudo.
- 2 vCPU e 4 GB RAM ou mais.
- Dois subdominios apontando para a VPS se for usar Nginx/SSL:
  - `app.seudominio.com` para o frontend.
  - `api.seudominio.com` para o backend.

## Instalacao padrao

```bash
curl -fsSL -o install-whaticket.sh https://raw.githubusercontent.com/jefersonflus/whaticket-backend/main/install-whaticket.sh
sudo bash install-whaticket.sh
```

Se os repositorios estiverem privados:

```bash
export GITHUB_TOKEN="seu_token_com_acesso"
curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
  -o install-whaticket.sh \
  https://raw.githubusercontent.com/jefersonflus/whaticket-backend/main/install-whaticket.sh
sudo -E bash install-whaticket.sh
```

## Instalacao com dominios e SSL

```bash
sudo FRONTEND_DOMAIN=app.seudominio.com \
  BACKEND_DOMAIN=api.seudominio.com \
  CERTBOT_EMAIL=admin@seudominio.com \
  ENABLE_SSL=true \
  bash install-whaticket.sh
```

## Instalacao a partir de zip

Zip unico contendo as pastas `backend/` e `frontend/`:

```bash
sudo SOURCE_ZIP=/root/whaticket.zip bash install-whaticket.sh
```

Zips separados:

```bash
sudo BACKEND_ZIP=/root/backend.zip FRONTEND_ZIP=/root/frontend.zip bash install-whaticket.sh
```

## Variaveis principais

- `INSTALL_DIR`: diretorio final. Padrao: `/opt/whaticket`.
- `APP_USER`: usuario Linux dos processos. Padrao: `whaticket`.
- `DB_NAME`: banco MySQL. Padrao: `whaticket`.
- `DB_USER`: usuario MySQL. Padrao: `whaticket`.
- `DB_PASSWORD`: senha MySQL. Se omitida, o instalador gera uma.
- `ADMIN_EMAIL`: email do admin inicial. Padrao: `admin@admin.com`.
- `ADMIN_PASSWORD`: senha do admin inicial. Se omitida, o instalador gera uma.
- `BACKEND_PORT`: porta interna da API. Padrao: `4000`.
- `FRONTEND_PORT`: porta interna do frontend. Padrao: `3000`.
- `SEED_DATABASE`: roda seeds iniciais. Padrao: `true`.
- `FORCE_ENV`: recria `.env` mesmo se ja existir. Padrao: `false`.

## Depois da instalacao

Credenciais geradas ficam em:

```bash
sudo cat /opt/whaticket/install-secrets.env
```

Comandos uteis:

```bash
sudo -u whaticket pm2 status
sudo -u whaticket pm2 logs whaticket-backend
sudo -u whaticket pm2 logs whaticket-frontend
```

Atualizacao manual:

```bash
cd /opt/whaticket/backend && sudo -u whaticket git pull --ff-only
cd /opt/whaticket/frontend && sudo -u whaticket git pull --ff-only
sudo bash /opt/whaticket/backend/install-whaticket.sh
```
