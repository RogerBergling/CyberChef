# ---------------------------------------------------------------------------
# Unpack and verify the immutable CyberChef release.
# ---------------------------------------------------------------------------
FROM alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f AS builder

# The base image is digest-pinned. These tools exist only in the builder stage.
# hadolint ignore=DL3018
RUN apk add --no-cache python3 unzip

WORKDIR /src
COPY source/ /src/source/
COPY scripts/csp-hashes.py scripts/prepare-index.py /src/scripts/

# Fail the build if either release artifact was modified, and confirm that the
# separate entry page is byte-identical to the copy inside the release ZIP.
RUN sha256sum -c source/SHA256SUMS \
    && unzip -p source/CyberChef_*.zip index.html.gz > /tmp/index.html.gz \
    && cmp -s /tmp/index.html.gz source/index.html.gz \
    && rm -f /tmp/index.html.gz

RUN mkdir -p /dist \
    && unzip -q source/CyberChef_*.zip -d /dist \
    && cp source/CyberChef_*.zip /dist/ \
    && gzip -dc source/index.html.gz > /dist/index.html \
    && rm -f /dist/index.html.gz /dist/index.html.br /dist/CyberChef_*.html \
    && find /dist -name '*.br' -delete

# Resolve CyberChef's unresolved download hash, inject the runtime pieces and
# move the loader SVG out of a data: URI.
RUN hash=$(sha256sum source/CyberChef_*.zip) \
    && hash=${hash%% *} \
    && python3 /src/scripts/prepare-index.py /dist/index.html "$hash" \
    && grep -q 'src="config.js"' /dist/index.html \
    && grep -q 'href=brand.css' /dist/index.html \
    && grep -q 'href=favicon.svg' /dist/index.html \
    && grep -q 'src="images/bombe.svg"' /dist/index.html \
    && grep -q "$hash" /dist/index.html \
    && ! grep -q DOWNLOAD_HASH_PLACEHOLDER /dist/index.html

# Hash the inline bootstrap scripts for a script-src without unsafe-inline.
# Keep this outside /dist so it is not published as a static file.
RUN python3 /src/scripts/csp-hashes.py /dist/index.html > /csp-script-src \
    && test -s /csp-script-src

# ---------------------------------------------------------------------------
# Runtime image.
# ---------------------------------------------------------------------------
FROM nginxinc/nginx-unprivileged:1.31-alpine@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e

ARG APP_VERSION=11.6.0
ARG CYBERCHEF_COMMIT=f464d62c7c943cda9749a765932a7548ba9bfb16
ARG IMAGE_TAG=local
ARG GIT_SHA=local
ARG BUILD_DATE

LABEL org.opencontainers.image.title="CyberChef" \
      org.opencontainers.image.description="CyberChef 11.6.0 packaged with a hardened, unprivileged nginx runtime." \
      org.opencontainers.image.source="https://github.com/RogerBergling/CyberChef" \
      org.opencontainers.image.url="https://github.com/RogerBergling/CyberChef" \
      org.opencontainers.image.documentation="https://github.com/RogerBergling/CyberChef#readme" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      io.rogerbergling.cyberchef.version="${APP_VERSION}" \
      io.rogerbergling.cyberchef.commit="${CYBERCHEF_COMMIT}" \
      io.rogerbergling.cyberchef.image-tag="${IMAGE_TAG}" \
      io.rogerbergling.cyberchef.build-date="${BUILD_DATE}"

# The base image defaults to uid 101. Build-time package updates, copies and
# metadata writes are done as root, then the final process drops back to 101.
USER root

# Apply fixed Alpine packages present in the pinned base image. CI scans the
# resulting image with Trivy.
RUN apk upgrade --no-cache
COPY --from=builder --chown=101:101 /dist /usr/share/nginx/html

COPY --chown=101:101 docker/favicon.svg /usr/share/nginx/html/favicon.svg
COPY --chown=101:101 docker/404.html /usr/share/nginx/html/404.html
COPY --chown=101:101 docker/security.txt /usr/share/nginx/html/.well-known/security.txt
COPY --chown=101:101 LICENSE NOTICE /usr/share/nginx/html/

COPY --chown=101:101 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=101:101 docker/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY --chown=101:101 docker/nginx.conf.template /usr/local/share/cyberchef/nginx.conf.template
COPY --chown=101:101 docker/brand.css.template /usr/local/share/cyberchef/brand.css.template
COPY --from=builder --chown=101:101 /csp-script-src /usr/local/share/cyberchef/csp-script-src

RUN chmod 0555 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh \
    && rm -f /usr/share/nginx/html/50x.html \
    && printf '{\n  "name": "CyberChef",\n  "cyberchefVersion": "%s",\n  "cyberchefCommit": "%s",\n  "imageVersion": "%s",\n  "imageTag": "%s",\n  "revision": "%s",\n  "buildDate": "%s"\n}\n' \
        "$APP_VERSION" "$CYBERCHEF_COMMIT" "$APP_VERSION" "$IMAGE_TAG" "$GIT_SHA" "$BUILD_DATE" \
        > /usr/share/nginx/html/version.json \
    && chown 101:101 /usr/share/nginx/html/version.json \
    && chmod 0444 /usr/share/nginx/html/version.json

USER 101
EXPOSE 8080
STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
