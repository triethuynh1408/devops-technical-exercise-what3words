# ---- build stage -----------------------------------------------------------
# Pinned to a patch release for reproducibility. A real pipeline would pin the
# digest as well and bump both via Renovate/Dependabot.
#
# go.mod declares `go 1.22`, but that's a language floor, not a toolchain pin:
# building with a current Go gets the latest stdlib security fixes into the
# binary (Trivy in CI flags the EOL 1.22 stdlib otherwise). No app changes.
FROM golang:1.26.8-bookworm AS build

# BuildKit provides these automatically; they let `docker buildx build
# --platform` cross-compile without QEMU (the build is pure Go, CGO is off).
ARG TARGETOS
ARG TARGETARCH

WORKDIR /src

# Copy the module definition first so `go mod download` is cached independently
# of source changes. This service has no third-party deps today, but wiring the
# layer correctly now costs nothing and pays off the moment one is added.
COPY app/go.mod ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY app/ ./

# Fail the image build if vet or the test suite fails: a broken binary should
# never get as far as being tagged.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go vet ./... && go test ./...

# CGO_ENABLED=0 -> a static binary with no libc dependency. This is what lets
# the final image be `distroless/static`, and it also sidesteps the macOS
# dyld "missing LC_UUID" quirk called out in the README.
# -trimpath drops local filesystem paths; -s -w strip the symbol table and
# DWARF to shrink the binary (~30%).
# Empty GOOS/GOARCH fall back to the build host's values, so a plain
# `docker build` still works; `docker buildx build --platform=...` sets them.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/greeter .

# ---- runtime stage -------------------------------------------------------------
# distroless/static: no shell, no package manager, no libc — just CA certs,
# /etc/passwd with a `nonroot` user (uid 65532), tzdata and /tmp. Nothing an
# attacker who lands RCE can pivot with.
FROM gcr.io/distroless/static-debian12:nonroot

# OCI metadata. VERSION is also passed to the app at runtime via env in the
# Helm chart; this label is just for `docker inspect` / registry UIs.
ARG VERSION=dev
LABEL org.opencontainers.image.title="greeter" \
      org.opencontainers.image.description="what3words DevOps exercise sample service" \
      org.opencontainers.image.source="https://github.com/triethuynh1408/devops-technical-exercise-what3words" \
      org.opencontainers.image.version="${VERSION}"

COPY --from=build /out/greeter /greeter

# Redundant with the base image's default, but explicit: never run as root.
# Numeric so the host / Kubernetes `runAsNonRoot` can always resolve it
# (65532 is distroless's "nonroot" user).
USER 65532:65532

# Documentation only (does not publish the port). Matches the app's default PORT.
EXPOSE 8080

# Exec form -> the binary is PID 1 and receives SIGTERM directly, which the
# app's graceful-shutdown sequence depends on.
ENTRYPOINT ["/greeter"]
