#!/bin/sh
# CyberChef container entrypoint.
#
# Renders runtime configuration from environment variables and starts nginx.
# This script runs as uid 101 and must only write beneath /tmp.
set -eu

log() {
    printf '%s\n' "cyberchef-entrypoint: $*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

# ---------------------------------------------------------------------------
# Defaults. Every value can be overridden through the environment.
# ---------------------------------------------------------------------------
: "${APP_PORT:=8080}"
: "${APP_THEME:=dark}"
: "${APP_TITLE:=CyberChef}"
: "${APP_FAVICON:=favicon.svg}"
: "${SERVER_NAME:=_}"
# An explicitly empty value disables real-IP handling; unset uses the default.
: "${TRUSTED_PROXY_CIDRS=192.168.0.0/18}"
: "${REAL_IP_HEADER:=X-Forwarded-For}"
: "${LOG_LEVEL:=warn}"
: "${ACCESS_LOG:=on}"
: "${NGINX_WORKER_PROCESSES:=2}"
: "${NGINX_WORKER_CONNECTIONS:=1024}"
: "${KEEPALIVE_TIMEOUT:=30s}"
: "${CLIENT_MAX_BODY_SIZE:=1m}"
: "${GZIP:=on}"
: "${GZIP_COMP_LEVEL:=5}"
: "${CACHE_HTML:=-1}"
: "${CACHE_ASSETS:=-1}"
: "${CACHE_MEDIA:=7d}"
: "${CACHE_DOWNLOAD:=1h}"
: "${PERMISSIONS_POLICY:=accelerometer=(), autoplay=(), camera=(), display-capture=(), encrypted-media=(), geolocation=(), gyroscope=(), hid=(), idle-detection=(), magnetometer=(), microphone=(), midi=(), payment=(), picture-in-picture=(), publickey-credentials-get=(), screen-wake-lock=(), serial=(), usb=(), xr-spatial-tracking=()}"
: "${CSP_DEFAULT_SRC:='self'}"
: "${CSP_STYLE_SRC:='self' 'unsafe-inline'}"
: "${CSP_IMG_SRC:='self' data: blob:}"
: "${CSP_FONT_SRC:='self' data:}"
: "${CSP_CONNECT_SRC:='self' blob:}"
: "${CSP_MEDIA_SRC:='self' data: blob:}"
: "${CSP_WORKER_SRC:='self' blob:}"
: "${CSP_CHILD_SRC:='self' blob:}"
: "${CSP_FRAME_SRC:='none'}"
: "${CSP_OBJECT_SRC:='none'}"
: "${CSP_BASE_URI:='none'}"
: "${CSP_FORM_ACTION:='none'}"
: "${CSP_FRAME_ANCESTORS:='none'}"
: "${CSP_MANIFEST_SRC:='self'}"
: "${BRAND_BG:=#070b14}"
: "${BRAND_BG_SOFT:=#0a1020}"
: "${BRAND_BG_ELEV:=#0d1526}"
: "${BRAND_LINE:=rgba(148, 163, 184, 0.18)}"
: "${BRAND_LINE_STRONG:=rgba(148, 163, 184, 0.34)}"
: "${BRAND_TEXT:=#e7eefb}"
: "${BRAND_TEXT_SOFT:=#c2cee2}"
: "${BRAND_MUTED:=#93a3bb}"
: "${BRAND_ACCENT:=#38bdf8}"
: "${BRAND_ACCENT_2:=#a78bfa}"
: "${BRAND_OK:=#34d399}"
: "${BRAND_WARN:=#fbbf24}"
: "${BRAND_DANGER:=#f87171}"

# ---------------------------------------------------------------------------
# Validation. Reject values that could break nginx/JavaScript or inject config.
# ---------------------------------------------------------------------------
reject_control() {
    # Reject CR, LF and other control characters in every rendered value.
    if printf '%s' "$2" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        die "$1 must not contain control characters"
    fi
}

require_uint() {
    case "$2" in
        ''|*[!0-9]*) die "$1 must be an integer" ;;
    esac
}

validate_nginx_value() {
    reject_control "$1" "$2"
    if printf '%s' "$2" | grep -q '["\\$]'; then
        die "$1 must not contain double quotes, backslashes or dollar signs"
    fi
}

validate_cache_value() {
    case "$2" in
        -1|off|epoch|max) return 0 ;;
    esac
    printf '%s' "$2" | grep -Eq '^[0-9]+[smhdwMy]?$' ||
        die "$1 must be -1, off, epoch, max, or a duration such as 7d"
}

# Theme aliases map to CyberChef's internal class names.
case "$APP_THEME" in
    dark|black) APP_THEME=dark ;;
    light|white|classic) APP_THEME=classic ;;
    geocities) APP_THEME=geocities ;;
    solarized-dark|solarizedDark) APP_THEME=solarizedDark ;;
    solarized-light|solarizedLight) APP_THEME=solarizedLight ;;
    *) die "APP_THEME must be dark, light, classic, geocities, solarized-dark or solarized-light" ;;
esac

require_uint APP_PORT "$APP_PORT"
[ "$APP_PORT" -ge 1024 ] && [ "$APP_PORT" -le 65535 ] ||
    die "APP_PORT must be between 1024 and 65535 (the container runs unprivileged)"

case "$NGINX_WORKER_PROCESSES" in
    auto) ;;
    *) require_uint NGINX_WORKER_PROCESSES "$NGINX_WORKER_PROCESSES"
       [ "$NGINX_WORKER_PROCESSES" -ge 1 ] && [ "$NGINX_WORKER_PROCESSES" -le 64 ] ||
           die "NGINX_WORKER_PROCESSES must be auto or 1-64" ;;
esac

require_uint NGINX_WORKER_CONNECTIONS "$NGINX_WORKER_CONNECTIONS"
[ "$NGINX_WORKER_CONNECTIONS" -ge 128 ] && [ "$NGINX_WORKER_CONNECTIONS" -le 65535 ] ||
    die "NGINX_WORKER_CONNECTIONS must be between 128 and 65535"

require_uint GZIP_COMP_LEVEL "$GZIP_COMP_LEVEL"
[ "$GZIP_COMP_LEVEL" -ge 1 ] && [ "$GZIP_COMP_LEVEL" -le 9 ] ||
    die "GZIP_COMP_LEVEL must be between 1 and 9"

case "$LOG_LEVEL" in
    debug|info|notice|warn|error|crit|alert|emerg) ;;
    *) die "LOG_LEVEL must be debug, info, notice, warn, error, crit, alert or emerg" ;;
esac

case "$ACCESS_LOG" in
    on) ACCESS_LOG_TARGET='/dev/stdout main' ;;
    off) ACCESS_LOG_TARGET=off ;;
    *) die "ACCESS_LOG must be on or off" ;;
esac

case "$GZIP" in
    on|off) ;;
    *) die "GZIP must be on or off" ;;
esac

case "$SERVER_NAME" in
    '_'|*[!A-Za-z0-9._*-]*) [ "$SERVER_NAME" = "_" ] || die "SERVER_NAME contains invalid characters" ;;
esac

case "$APP_FAVICON" in
    //*|*..*|*://*|*[!A-Za-z0-9._/-]*) die "APP_FAVICON must be a local relative path" ;;
esac

printf '%s' "$CLIENT_MAX_BODY_SIZE" | grep -Eq '^[0-9]+[kKmMgG]?$' ||
    die "CLIENT_MAX_BODY_SIZE must look like 1m or 1048576"

printf '%s' "$KEEPALIVE_TIMEOUT" | grep -Eq '^[0-9]+[smhd]?$' ||
    die "KEEPALIVE_TIMEOUT must look like 30s"

printf '%s' "$REAL_IP_HEADER" | grep -Eq '^[A-Za-z0-9-]+$' ||
    die "REAL_IP_HEADER must be an HTTP header name"

# Keep the generated branding stylesheet injection-free and simple.
printf '%s' "$BRAND_LINE" | grep -Eq \
    '^(#[0-9A-Fa-f]{6}|rgba\([0-9]{1,3}(, ?[0-9]{1,3}){2}, ?(0|1|0?\.[0-9]+)\))$' ||
    die "BRAND_LINE must be a hex colour or rgba() value"
printf '%s' "$BRAND_LINE_STRONG" | grep -Eq \
    '^(#[0-9A-Fa-f]{6}|rgba\([0-9]{1,3}(, ?[0-9]{1,3}){2}, ?(0|1|0?\.[0-9]+)\))$' ||
    die "BRAND_LINE_STRONG must be a hex colour or rgba() value"

printf '%s' "$APP_TITLE" | LC_ALL=C grep -Eq '^[ -~]+$' ||
    die "APP_TITLE must be printable ASCII"

validate_cache_value CACHE_HTML "$CACHE_HTML"
validate_cache_value CACHE_ASSETS "$CACHE_ASSETS"
validate_cache_value CACHE_MEDIA "$CACHE_MEDIA"
validate_cache_value CACHE_DOWNLOAD "$CACHE_DOWNLOAD"

for name in APP_TITLE PERMISSIONS_POLICY CSP_DEFAULT_SRC CSP_STYLE_SRC CSP_IMG_SRC \
    CSP_FONT_SRC CSP_CONNECT_SRC CSP_MEDIA_SRC CSP_WORKER_SRC CSP_CHILD_SRC \
    CSP_FRAME_SRC CSP_OBJECT_SRC CSP_BASE_URI CSP_FORM_ACTION CSP_FRAME_ANCESTORS \
    CSP_MANIFEST_SRC BRAND_BG BRAND_BG_SOFT BRAND_BG_ELEV BRAND_LINE BRAND_LINE_STRONG \
    BRAND_TEXT BRAND_TEXT_SOFT BRAND_MUTED BRAND_ACCENT BRAND_ACCENT_2 BRAND_OK \
    BRAND_WARN BRAND_DANGER; do
    value=
    eval "value=\${$name}"
    reject_control "$name" "$value"
done

for name in BRAND_BG BRAND_BG_SOFT BRAND_BG_ELEV BRAND_ACCENT BRAND_ACCENT_2 \
    BRAND_TEXT BRAND_TEXT_SOFT BRAND_MUTED BRAND_OK BRAND_WARN BRAND_DANGER; do
    value=
    eval "value=\${$name}"
    printf '%s' "$value" | grep -Eq '^#[0-9A-Fa-f]{6}$' ||
        die "$name must be a six-digit hex colour such as #38bdf8"
done

# ---------------------------------------------------------------------------
# CSP script-src. The inline bootstrap scripts are hashed at image build.
# ---------------------------------------------------------------------------
if [ -z "${CSP_SCRIPT_SRC:-}" ]; then
    [ -r /usr/local/share/cyberchef/csp-script-src ] ||
        die "missing /usr/local/share/cyberchef/csp-script-src"
    CSP_SCRIPT_SRC=$(cat /usr/local/share/cyberchef/csp-script-src)
fi
reject_control CSP_SCRIPT_SRC "$CSP_SCRIPT_SRC"

CSP_HEADER="default-src ${CSP_DEFAULT_SRC}; script-src ${CSP_SCRIPT_SRC}; style-src ${CSP_STYLE_SRC}; img-src ${CSP_IMG_SRC}; font-src ${CSP_FONT_SRC}; connect-src ${CSP_CONNECT_SRC}; media-src ${CSP_MEDIA_SRC}; worker-src ${CSP_WORKER_SRC}; child-src ${CSP_CHILD_SRC}; frame-src ${CSP_FRAME_SRC}; object-src ${CSP_OBJECT_SRC}; base-uri ${CSP_BASE_URI}; form-action ${CSP_FORM_ACTION}; frame-ancestors ${CSP_FRAME_ANCESTORS}; manifest-src ${CSP_MANIFEST_SRC}"

validate_nginx_value CSP_HEADER "$CSP_HEADER"
validate_nginx_value PERMISSIONS_POLICY "$PERMISSIONS_POLICY"
validate_nginx_value SERVER_NAME "$SERVER_NAME"

# JSON-escape the title for config.js. Values with control characters were
# rejected above; quotes and backslashes are escaped here.
APP_TITLE_JSON=$(printf '%s' "$APP_TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')

# ---------------------------------------------------------------------------
# Writable runtime directory. Compose mounts /tmp as tmpfs.
# ---------------------------------------------------------------------------
RUNTIME_DIR=/tmp/nginx
rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"/client_temp "$RUNTIME_DIR"/proxy_temp \
    "$RUNTIME_DIR"/fastcgi_temp "$RUNTIME_DIR"/uwsgi_temp "$RUNTIME_DIR"/scgi_temp

# ---------------------------------------------------------------------------
# Real client IPs from HAProxy. Only listed CIDRs may set the header.
# ---------------------------------------------------------------------------
: > "$RUNTIME_DIR/realip.conf"
if [ -n "$TRUSTED_PROXY_CIDRS" ]; then
    OLD_IFS=$IFS
    IFS=,
    for cidr in $TRUSTED_PROXY_CIDRS; do
        # Trim surrounding whitespace.
        cidr=$(printf '%s' "$cidr" | tr -d '[:space:]')
        [ -n "$cidr" ] || continue
        printf '%s' "$cidr" | grep -Eq '^[0-9A-Fa-f:./]+$' ||
            die "TRUSTED_PROXY_CIDRS contains an invalid CIDR: $cidr"
        printf 'set_real_ip_from %s;\n' "$cidr" >> "$RUNTIME_DIR/realip.conf"
    done
    IFS=$OLD_IFS
    if [ -s "$RUNTIME_DIR/realip.conf" ]; then
        printf 'real_ip_header %s;\n' "$REAL_IP_HEADER" >> "$RUNTIME_DIR/realip.conf"
        printf 'real_ip_recursive on;\n' >> "$RUNTIME_DIR/realip.conf"
    fi
fi
validate_nginx_value REAL_IP_HEADER "$REAL_IP_HEADER"

# ---------------------------------------------------------------------------
# Theme/config bootstrap. Runs before CyberChef's inline bootstrap.
# ---------------------------------------------------------------------------
cat > "$RUNTIME_DIR/config.js" <<EOF
(function () {
    "use strict";
    var theme = "${APP_THEME}";
    var title = "${APP_TITLE_JSON}";
    var icon = "${APP_FAVICON}";
    try {
        var raw = localStorage.getItem("options");
        var options = raw ? JSON.parse(raw) : {};
        if (!options || typeof options !== "object" || Array.isArray(options)) {
            options = {};
        }
        if (!options.theme) {
            options.theme = theme;
            localStorage.setItem("options", JSON.stringify(options));
        }
        document.documentElement.className = options.theme || theme;
    } catch (e) {
        document.documentElement.className = theme;
    }
    if (title) {
        document.title = title;
        if (title !== "CyberChef" && window.MutationObserver) {
            try {
                var titleElement = document.querySelector("title");
                var rebrandTitle = function () {
                    var current = document.title;
                    var appSuffix = " - CyberChef";
                    var baseSuffix = " - " + title;
                    if (current === title || current.slice(-baseSuffix.length) === baseSuffix) {
                        return;
                    }
                    if (current === "CyberChef") {
                        document.title = title;
                    } else if (current.slice(-appSuffix.length) === appSuffix) {
                        document.title = current.slice(0, -appSuffix.length) + baseSuffix;
                    } else {
                        document.title = title;
                    }
                };
                if (titleElement) {
                    window.__cyberChefTitleObserver = new MutationObserver(rebrandTitle);
                    window.__cyberChefTitleObserver.observe(titleElement, {
                        childList: true,
                        subtree: true,
                        characterData: true
                    });
                }
                rebrandTitle();
            } catch (e) {
                /* Keep the initial title if the observer is unavailable. */
            }
        }
    }
    var link = document.querySelector('link[rel="icon"]');
    if (link) {
        link.href = icon;
    }
})();
EOF

# ---------------------------------------------------------------------------
# Brand stylesheet. Rendered from the template with validated colours.
# ---------------------------------------------------------------------------
export BRAND_BG BRAND_BG_SOFT BRAND_BG_ELEV BRAND_LINE BRAND_LINE_STRONG \
    BRAND_TEXT BRAND_TEXT_SOFT BRAND_MUTED BRAND_ACCENT BRAND_ACCENT_2 \
    BRAND_OK BRAND_WARN BRAND_DANGER
# shellcheck disable=SC2016 # envsubst needs literal ${NAME} expressions.
envsubst '${BRAND_BG} ${BRAND_BG_SOFT} ${BRAND_BG_ELEV} ${BRAND_LINE} ${BRAND_LINE_STRONG} ${BRAND_TEXT} ${BRAND_TEXT_SOFT} ${BRAND_MUTED} ${BRAND_ACCENT} ${BRAND_ACCENT_2} ${BRAND_OK} ${BRAND_WARN} ${BRAND_DANGER}' \
    < /usr/local/share/cyberchef/brand.css.template > "$RUNTIME_DIR/brand.css"

# ---------------------------------------------------------------------------
# nginx configuration.
# ---------------------------------------------------------------------------
export APP_PORT SERVER_NAME LOG_LEVEL ACCESS_LOG_TARGET NGINX_WORKER_PROCESSES \
    NGINX_WORKER_CONNECTIONS KEEPALIVE_TIMEOUT CLIENT_MAX_BODY_SIZE GZIP \
    GZIP_COMP_LEVEL CACHE_HTML CACHE_ASSETS CACHE_MEDIA CACHE_DOWNLOAD \
    CSP_HEADER PERMISSIONS_POLICY

# shellcheck disable=SC2016 # envsubst needs literal ${NAME} expressions.
envsubst '${APP_PORT} ${SERVER_NAME} ${LOG_LEVEL} ${ACCESS_LOG_TARGET} ${NGINX_WORKER_PROCESSES} ${NGINX_WORKER_CONNECTIONS} ${KEEPALIVE_TIMEOUT} ${CLIENT_MAX_BODY_SIZE} ${GZIP} ${GZIP_COMP_LEVEL} ${CACHE_HTML} ${CACHE_ASSETS} ${CACHE_MEDIA} ${CACHE_DOWNLOAD} ${CSP_HEADER} ${PERMISSIONS_POLICY}' \
    < /usr/local/share/cyberchef/nginx.conf.template > "$RUNTIME_DIR/nginx.conf"

# Test the generated configuration before serving traffic.
nginx -t -c "$RUNTIME_DIR/nginx.conf" >/dev/null

log "starting nginx on :${APP_PORT} (theme=${APP_THEME}, title=${APP_TITLE})"

# Allow `docker run image sh` for debugging without starting nginx.
if [ "$#" -gt 0 ] && [ "$1" != "nginx" ]; then
    exec "$@"
fi

exec nginx -c "$RUNTIME_DIR/nginx.conf" -g 'daemon off;'
