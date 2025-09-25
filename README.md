# WoW BiS Recommender

A monorepo for building **Best-in-Slot (BiS) recommendations** for World of Warcraft specs and seasons.

## 🚀 Stack
- **Backend:** FastAPI + Poetry + SQLModel + Redis + APScheduler (ETL)
- **Frontend:** SvelteKit + Tailwind
- **Database:** Postgres
- **Cache / PubSub:** Redis
- **Dev environment:** Docker Compose with hot reload

## 🛠️ Development

### Prerequisites
- [Docker](https://www.docker.com/) + [Docker Compose](https://docs.docker.com/compose/)
- [Make](https://www.gnu.org/software/make/) (optional, for shortcuts)

### Start dev environment
```bash
make dev
```

This launches:
- **FastAPI** at [http://localhost:8000](http://localhost:8000)
- **SvelteKit** at [http://localhost:5173](http://localhost:5173)
- **Postgres** at `localhost:5432` (`postgres/postgres`)
- **Redis** at `localhost:6379`

### Stop environment
```bash
make stop
```

### Logs
```bash
make logs
```

### Run tests
```bash
make test
```

### Format & lint
```bash
make lint
```

## 🔧 Notes
- Environment variables live in `backend/.env.example` and `frontend/.env.example`.
- Poetry manages backend dependencies, pnpm manages frontend.
- For one-off commands inside containers:
  ```bash
  docker compose exec api poetry run alembic upgrade head
  docker compose exec web pnpm build
  ```

## 📜 License
MIT
