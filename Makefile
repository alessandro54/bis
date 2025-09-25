---

# 📄 `Makefile`

```make
# Makefile for wow-bis monorepo

.PHONY: dev stop logs build rebuild test lint fmt

dev: ## Run dev stack (Docker Compose up)
	docker compose up --build

stop: ## Stop and remove containers/volumes
	docker compose down -v

logs: ## Tail logs from all services
	docker compose logs -f

build: ## Build Docker images
	docker compose build

rebuild: ## Build without cache
	docker compose build --no-cache

test: ## Run backend tests inside container
	docker compose exec api poetry run pytest -q

lint: ## Run Ruff + Black linting
	docker compose exec api poetry run ruff check .
	docker compose exec api poetry run black --check .
	docker compose exec web pnpm lint

fmt: ## Autoformat backend (ruff/black) + frontend (eslint/prettier)
	docker compose exec api poetry run ruff check --fix .
	docker compose exec api poetry run black .
	docker compose exec web pnpm lint --fix || true
	docker compose exec web pnpm format || true
