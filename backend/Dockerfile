# SPAI server.
#
# Runs anywhere that runs a container. Two things the host must provide:
#   - a persistent disk mounted at /data (the database lives there)
#   - HTTPS in front of it (every managed host does this for you)
#
# Hugging Face Spaces' free tier wipes the disk on restart, which loses
# every student record. Use a host with a persistent volume.

FROM python:3.11-slim

# System libraries OpenCV / Ultralytics need at runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Run as an unprivileged user, with a writable data folder.
RUN useradd -m -u 1000 user && mkdir -p /data && chown user:user /data
USER user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH \
    SPAI_DB=/data/spai.db \
    PYTHONUNBUFFERED=1

WORKDIR /home/user/app

# Python deps first so Docker caches this layer. CPU-only torch is much
# smaller than the CUDA build and fast enough for these models.
COPY --chown=user requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir -r requirements.txt

COPY --chown=user . .

# Most hosts tell the app which port to use in $PORT.
ENV PORT=8000
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s CMD python -c "import urllib.request,os; urllib.request.urlopen(f'http://127.0.0.1:{os.environ[\"PORT\"]}/health')"

# --proxy-headers: trust the host's HTTPS proxy, so sign-in cookies are
# marked secure and pairing codes show the https:// address.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips='*'"]
