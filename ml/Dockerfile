# Model server for dota2bot-neigh. Stdlib-only, works on arm64 (OrangePi) and amd64.
FROM python:3.12-slim

WORKDIR /app
COPY server.py train.py ./

# dataset + trained model live on a volume so they survive container rebuilds
ENV ML_HOST=0.0.0.0 \
    ML_PORT=5544 \
    ML_DATA_DIR=/data \
    ML_MODEL_PATH=/data/model.json
VOLUME /data
EXPOSE 5544

CMD ["python3", "server.py"]
