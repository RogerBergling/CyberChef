# Security policy

## Reporting a vulnerability

Email **github@bergling.net** with:

- the affected URL, image tag, file or Compose setting,
- a short description of the issue,
- reproduction steps or a proof of concept,
- the browser, client or container runtime you used.

Please do not open a public GitHub issue for a security report. I aim to
acknowledge reports within a few days.

## Scope

This repository packages the upstream CyberChef application and adds a hardened
nginx runtime, runtime configuration, branding and CI. Relevant reports include:

- container escape, privilege escalation or writable-rootfs issues,
- nginx or Compose misconfiguration that exposes the app or spoofs client IPs,
- a Content-Security-Policy or security-header weakness introduced here,
- injection into the generated nginx configuration or browser configuration,
- a supply-chain issue in the Dockerfile, GitHub Actions or release artifacts,
- a difference between the bundled CyberChef build and its documented hash.

Reports about the CyberChef application itself belong upstream:
<https://github.com/gchq/CyberChef/security>. If the packaging makes an upstream
issue worse, report that part here as well.

## Security model

- Static files only. No backend, database, accounts or server-side processing.
- CyberChef input and recipes are processed in the visitor's browser and are not
  sent to this server.
- The container runs as uid 101, read-only, with all capabilities dropped and
  `no-new-privileges`.
- TLS is **not** handled by this container. HAProxy in front is responsible for
  TLS, HSTS, authentication (if required) and network ACLs.
- The default CSP blocks CyberChef's generic HTTP request operation, DNS over
  HTTPS and map tiles. Relaxing `CSP_CONNECT_SRC` or `CSP_IMG_SRC` is an explicit
  operator decision and can permit data exfiltration by a recipe.
- CSP allows inline styles and WebAssembly compilation (`'wasm-unsafe-eval'`)
  because CyberChef needs them. It does not allow JavaScript `eval`, inline
  scripts or inline event handlers.
- A compromised browser, extension, host or reverse proxy is outside the scope
  of this repository.

## Out of scope

- Automated scanner output without a reproducible issue.
- Denial-of-service or resource-exhaustion reports.
- Social engineering, physical access or compromised endpoints.
- Vulnerabilities in upstream CyberChef that are not caused or worsened by this
  packaging (report them upstream).
- Operations intentionally blocked by the default CSP.

## No bug bounty

This is a personal, non-commercial project. There is no bug bounty, but a clear,
responsible report is genuinely appreciated.
