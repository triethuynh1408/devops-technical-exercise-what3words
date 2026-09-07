# Decisions

Why the solution looks the way it does. Written as I went, tidied at the end.
The commits cover *what* changed.

Status: in progress.

---

## Task 1 — Container image

Two-stage `Dockerfile`. Build stage on `golang:1.22.12-bookworm` runs `go vet` and
`go test ./...` before the build, so a broken test suite can't produce a tagged image —
worth doing while there's no CI yet. Then `CGO_ENABLED=0 go build -trimpath -ldflags="-s -w"`
for a static, stripped binary.

Runtime stage is `gcr.io/distroless/static-debian12:nonroot`: the binary on top of CA
certs and `/etc/passwd`, nothing else. No shell, no package manager, no libc. Runs as
uid 65532, `ENTRYPOINT` in exec form so the binary is PID 1 and gets `SIGTERM` directly —
the app's drain sequence depends on that. ~13 MB.

`CGO_ENABLED=0` is what makes the static base possible in the first place; it also happens
to dodge the macOS dyld quirk the README mentions.

I looked at `scratch` (no certs, no `/etc/passwd`, no `/tmp` — you end up rebuilding what
distroless already gives you) and `alpine` (ships busybox and apk, bigger attack surface
for no benefit here). `chainguard/static` would have been a fine choice too; I went with
distroless on familiarity.

`GREETING_NAME` is not baked in. It's required and per-environment, and the app is designed
to fail fast without it — baking a default would just hide misconfiguration.

**Least sure about:** I pinned the builder to a patch tag but left the base on `:nonroot`
rather than a digest. For anything production-facing I'd pin both by digest and let
Renovate bump them. Also, I only build for the host arch (arm64) since the local kind
nodes are arm64 and there's no registry here; a real image would be a multi-arch manifest.

Verified locally: build and tests pass, container runs non-root as PID 1, `/healthz` stays
200 through warm-up while `/readyz` is 503 then flips to 200, and `SIGTERM` drains an
in-flight `/work` request before the process exits 0.

---

## Task 2 — Local Kubernetes cluster

_TODO_

## Task 3 — Packaging

_TODO_

## Task 4 — Terraform

_TODO_

## Extensions — order and why

_TODO_

## What's missing / next

_TODO_
