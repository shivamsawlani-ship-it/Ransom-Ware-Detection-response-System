FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY scripts ./scripts
COPY config.yaml .

# Run as an unprivileged user; data/logs/reports are mounted volumes.
RUN useradd --create-home rdrs \
    && mkdir -p data/sandbox logs reports \
    && chown -R rdrs:rdrs /app
USER rdrs

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)"

# 0.0.0.0 is the *container* address; compose publishes it on localhost only.
CMD ["python", "-m", "app.main", "--serve", "--host", "0.0.0.0"]
