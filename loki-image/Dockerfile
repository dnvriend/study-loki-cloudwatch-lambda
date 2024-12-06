FROM public.ecr.aws/docker/library/python:3.13-bookworm

ENV VERSION="3.3.1"

ENV LOKI_NAME="loki-linux-amd64"

ENV LOKI_ZIP_NAME="${LOKI_NAME}.zip"

WORKDIR app

COPY requirements.txt requirements.txt

RUN pip install -r requirements.txt && \
  wget "https://github.com/grafana/loki/releases/download/v${VERSION}/${LOKI_ZIP_NAME}" && \
  unzip "${LOKI_ZIP_NAME}" && \
  rm "${LOKI_ZIP_NAME}" && \
  mv ${LOKI_NAME} loki && \
  mkdir boltdb-shipper-active && \
  mkdir boltdb-shipper-cache && \
  mkdir compactor

COPY ./config/config.yaml config.yaml

# loki -config.expand-env
ENTRYPOINT ["/app/loki", "-config.expand-env"]
