# SPAI backend on Hugging Face Spaces.
# HF Spaces expects the app to listen on port 7860.

FROM python:3.11-slim

# System deps that OpenCV/Ultralytics need at runtime.
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# HF Spaces runs as a non-root user (uid 1000). Set up a home dir
# so caches (torch, ultralytics) have somewhere writable to live.
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH

WORKDIR /home/user/app

# Install Python deps first so Docker caches this layer.
# Install CPU-only torch explicitly — it's much smaller than the CUDA build
# and HF free Spaces have no GPU anyway.
COPY --chown=user requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir -r requirements.txt

# Copy the rest of the backend (app code + the model).
COPY --chown=user . .

# HF Spaces standard port.
EXPOSE 7860

# Start the API on 7860.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "7860"]
