ARG PYTHON_VERSION=3.11
FROM python:${PYTHON_VERSION}-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    git \
    ca-certificates \
    openssl \
    tar \
    tzdata \
    gcc \
    g++ \
    make \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -d /home/container container

COPY docker/start-container.sh /usr/local/bin/start-container.sh
RUN chmod +x /usr/local/bin/start-container.sh

ENV USER=container HOME=/home/container
WORKDIR /mnt/server

EXPOSE 8080

CMD ["/usr/local/bin/start-container.sh"]
