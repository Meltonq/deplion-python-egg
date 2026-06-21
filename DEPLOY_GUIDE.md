# Python Egg v2: Quickstart + FAQ

## Первый запуск за 7 шагов (First run in 7 steps)

1. Импортируй `python-egg.json` в Pterodactyl и создай сервер на образе `Python 3.11` (или `3.10`/`3.12`/`3.13`).
2. Оставь дефолты для быстрого старта:
    - `PACKAGE_MANAGER=pip`
    - `START_CMD=python main.py`
    - `ENABLE_BUILD=false`
    - `ENABLE_BUILD_ON_START=false`
3. Запусти сервер один раз и дождись строки `Python application started`.
4. Если проекта ещё нет (нет `main.py`, `app.py`, `requirements.txt`, `pyproject.toml`, `Pipfile`), установщик автоматически создаст минимальное Python-приложение.
5. Если нужна сборка только при установке:
    - `ENABLE_BUILD=true`
    - `BUILD_CMD=python setup.py build` (или любая другая команда)
6. Если нужна сборка перед каждым стартом:
    - `ENABLE_BUILD_ON_START=true`
    - `BUILD_CMD=<твоя команда сборки>`
7. После изменений Startup-переменных перезапусти сервер.

## Пакетные менеджеры

| Менеджер | Файл зависимостей    | Хранение пакетов             |
|----------|----------------------|------------------------------|
| `pip`    | `requirements.txt` или `pyproject.toml` | `packages/` директория (persisted) |
| `uv`     | `requirements.txt` или `pyproject.toml` | `packages/` директория (persisted) |
| `poetry` | `pyproject.toml`     | `.venv/` в директории проекта (persisted) |
| `pipenv` | `Pipfile`            | `.venv/` в директории проекта (persisted) |

**pip и uv** устанавливают пакеты в `packages/` — они персистентны между перезапусками.

**poetry и pipenv** создают `.venv/` в корне проекта — тоже персистентно. При запуске egg автоматически активирует окружение.

## START_CMD: что можно запустить

```
python main.py
python bot.py
python -m uvicorn main:app --host 0.0.0.0 --port ${PORT}
python -m gunicorn -b 0.0.0.0:${PORT} main:app
python -m flask run --host 0.0.0.0 --port ${PORT}
```

> **Важно:** для poetry/pipenv-проектов консольные скрипты (например, `uvicorn`) запускай через `python -m uvicorn`, так как egg автоматически исправляет shebangs при старте.

## Network behavior

- Python-приложение должно слушать порт из переменной `PORT`.
- На старте egg выставляет `PORT=${SERVER_PORT}`.
- Слушай `0.0.0.0`, а не только `127.0.0.1`.

## Troubleshooting FAQ

### 1) Приложение не стартует

Проверь:

- корректна ли `START_CMD`
- существует ли файл, который запускаешь
- запускается ли команда вручную в консоли сервера

### 2) Пакет не найден (ModuleNotFoundError)

Проверь:

- правильно ли указан `PACKAGE_MANAGER`
- есть ли зависимость в `requirements.txt` / `pyproject.toml` / `Pipfile`
- установщик завершился успешно (нет ошибок в логах установки)

### 3) Build не запускается

Проверь нужный toggle:

- install build: `ENABLE_BUILD=true`
- startup build: `ENABLE_BUILD_ON_START=true`
- в обоих случаях `BUILD_CMD` должен быть непустым и валидным

### 4) Приложение запущено, но недоступно

Проверь:

- приложение реально слушает `PORT`
- приложение слушает `0.0.0.0`, а не только `127.0.0.1`
- `SERVER_PORT` назначен панелью корректно

### 5) poetry/pipenv: консольная команда не найдена

Используй вместо этого `python -m <module>`:
- вместо `uvicorn` → `python -m uvicorn`
- вместо `gunicorn` → `python -m gunicorn`
- вместо `flask` → `python -m flask`

## Build and publish images

```bash
docker build --build-arg PYTHON_VERSION=3.10 -t ghcr.io/lias1n/python-egg:py310 .
docker build --build-arg PYTHON_VERSION=3.11 -t ghcr.io/lias1n/python-egg:py311 .
docker build --build-arg PYTHON_VERSION=3.12 -t ghcr.io/lias1n/python-egg:py312 .
docker build --build-arg PYTHON_VERSION=3.13 -t ghcr.io/lias1n/python-egg:py313 .
```

```bash
echo <GITHUB_TOKEN> | docker login ghcr.io -u <GITHUB_USERNAME> --password-stdin
docker push ghcr.io/lias1n/python-egg:py310
docker push ghcr.io/lias1n/python-egg:py311
docker push ghcr.io/lias1n/python-egg:py312
docker push ghcr.io/lias1n/python-egg:py313
```
