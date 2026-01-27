# Базовый образ с Python и uv
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

#RUN apt-get update && apt-get install -y --no-install-recommends     curl build-essential libpq-dev     && rm -rf /var/lib/apt/lists/*

#COPY pyproject.toml* uv.lock* requirements.txt* ./
#RUN --mount=type=cache,target=/root/.cache/uv     if [ -f pyproject.toml ]; then         uv sync --locked --no-install-project;     elif [ -f requirements.txt ]; then         uv pip install -r requirements.txt;     fi

#ENV UV_PROJECT_ENVIRONMENT=.venv
#ENV PATH="/app/.venv/bin:$PATH"

# текст  CMD ["uv", "run", "python", "src/main.py"]


# Создаём тестовый файл main.py
RUN echo 'print("✅ UV работает внутри Docker!")' > main.py

# Команда по умолчанию
CMD ["uv", "run", "python", "main.py"]