# syntax=docker/dockerfile:1

# ---------- 1. Flutter web aplikacija ----------
ARG FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:stable
FROM ${FLUTTER_IMAGE} AS web
WORKDIR /src/app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get
COPY app/ ./
# --no-web-resources-cdn: CanvasKit se služi sa našeg servera (stroga CSP, bez Google CDN-a)
RUN flutter build web --release --no-web-resources-cdn --no-wasm-dry-run

# ---------- 2. Dart server ----------
FROM dart:stable AS server
WORKDIR /src/server
COPY server/pubspec.yaml server/pubspec.lock ./
RUN dart pub get
COPY server/ ./
RUN dart build cli -o /out

# ---------- 3. Minimalna slika za rad ----------
# Ista Debian verzija kao dart:stable (glibc), bez apt-a: sertifikati se kopiraju.
FROM debian:trixie-slim
COPY --from=server /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
RUN useradd --system --uid 10001 --home /app fotograf \
 && mkdir -p /data && chown fotograf /data
WORKDIR /app
COPY --from=server /out/bundle/ /app/
COPY --from=web /src/app/build/web /app/web
ENV WEB_DIR=/app/web \
    DATA_DIR=/data \
    PORT=8080 \
    HOST=0.0.0.0 \
    TZ=Europe/Belgrade
USER fotograf
VOLUME ["/data"]
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD ["/bin/bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080"]
ENTRYPOINT ["/app/bin/server"]
