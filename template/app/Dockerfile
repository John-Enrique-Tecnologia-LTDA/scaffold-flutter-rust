# Build do app Flutter para web e publicação via nginx, que também faz o proxy
# das rotas /api para o container do backend (o cliente Dart usa a mesma origem).
#
# O SDK vem do tarball oficial, pinado: as imagens da comunidade ficam meses
# atrás do canal stable e não atendem o Dart exigido pelo pubspec.
FROM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.47.4
ENV PATH=/opt/flutter/bin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
       | tar -xJ -C /opt \
    && git config --global --add safe.directory /opt/flutter \
    && flutter --version

WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

FROM nginx:1.27-alpine
COPY --from=build /src/build/web /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template

# Só as variáveis com este prefixo são interpoladas, as do nginx ($host, $uri) ficam intactas.
ENV NGINX_ENVSUBST_FILTER={= env_prefix =}
ENV {= env_prefix =}_API_HOST={= name =}-api:8080
EXPOSE 80
