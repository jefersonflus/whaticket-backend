# Whaticket Backend

Backend Node.js/TypeScript do Whaticket, separado para publicacao independente no GitHub.

## Instalacao rapida da stack completa

Este repositorio inclui o instalador completo do Whaticket. Ele baixa e posiciona backend e frontend, instala dependencias do sistema, cria banco MySQL, configura Redis, gera `.env`, executa migrations/seeds, compila os projetos e sobe os processos no PM2.

```bash
curl -fsSL -o install-whaticket.sh https://raw.githubusercontent.com/jefersonflus/whaticket-backend/main/install-whaticket.sh
sudo bash install-whaticket.sh
```

Se os repositorios estiverem privados, informe um token com acesso de leitura:

```bash
export GITHUB_TOKEN="seu_token"
curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
  -o install-whaticket.sh \
  https://raw.githubusercontent.com/jefersonflus/whaticket-backend/main/install-whaticket.sh
sudo -E bash install-whaticket.sh
```

Tambem e possivel instalar a partir de zips locais:

```bash
sudo SOURCE_ZIP=/caminho/whaticket.zip bash install-whaticket.sh
```

Veja o passo a passo completo em [docs/INSTALL.md](docs/INSTALL.md).

## Desenvolvimento local do backend

```bash
cp .env.example .env
npm install
npm run build
npx sequelize db:migrate
npx sequelize db:seed:all
npm run dev:server
```

Usuario inicial criado pelo seed:

- Email: `admin@admin.com`
- Senha padrao: `123456`

Em instalacoes automatizadas, o script gera uma senha aleatoria e salva em `/opt/whaticket/install-secrets.env`.
