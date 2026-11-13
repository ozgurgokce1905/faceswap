# FaceSwap hazır imajı: FaceFusion + Python paketleri + tüm modeller içinde.
# Pod açılınca kurulum/indirme YOK, 1-2 dk'da hazır. GitHub Actions bunu otomatik derler (.github/workflows/imaj.yml).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 PYTHONIOENCODING=utf-8 PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3.12 python3.12-venv python3-pip git curl ca-certificates ffmpeg libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# FaceFusion (sabit sürüm 3.9.2)
ARG FF_COMMIT=decc6c9
RUN git clone -q https://github.com/facefusion/facefusion.git /opt/facefusion \
    && git -C /opt/facefusion checkout -q $FF_COMMIT && rm -rf /opt/facefusion/.git

# Python ortamı (CUDA/cuDNN pip paketlerinden gelir, sürücü pod'un kendisinden)
RUN python3.12 -m venv /opt/venv && /opt/venv/bin/pip install -q --upgrade pip \
    && grep -v '^onnxruntime' /opt/facefusion/requirements.txt > /tmp/req.txt \
    && /opt/venv/bin/pip install -r /tmp/req.txt "onnxruntime-gpu==1.24.4" \
       nvidia-cuda-runtime-cu12 nvidia-cudnn-cu12 nvidia-cublas-cu12 nvidia-cufft-cu12 \
       nvidia-curand-cu12 nvidia-cuda-nvrtc-cu12 nvidia-nvjitlink-cu12 \
       fastapi uvicorn python-multipart requests \
    && /opt/venv/bin/python -c "import onnxruntime, cv2, numpy, gradio, fastapi; print('paketler tamam')"

# Sunucu kodu
COPY sunucu /opt/fs/sunucu
COPY runpod /opt/fs/runpod
ARG VERSION=0
RUN echo "$VERSION" > /opt/fs/VERSION \
    && cp /opt/fs/sunucu/sitecustomize.py $(/opt/venv/bin/python -c "import site;print(site.getsitepackages()[0])")/sitecustomize.py \
    && sed -i 's/\r$//' /opt/fs/runpod/*.sh

# Tüm modelleri imajın içine indir (~2.5 GB) -> pod'da indirme beklenmez
RUN mkdir -p /tmp/fsdata && FACESWAP_HOME=/tmp/fsdata FACESWAP_FF_DIR=/opt/facefusion FACESWAP_PROVIDER=cpu \
    /opt/venv/bin/python /opt/fs/sunucu/warmup.py && rm -rf /tmp/fsdata

ENV FACESWAP_WAN=0
EXPOSE 8765
CMD ["bash", "/opt/fs/runpod/image_start.sh"]
