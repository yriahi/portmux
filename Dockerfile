# Stage 1: Builder
# --platform=$BUILDPLATFORM pins the builder to the runner's native arch (avoids QEMU emulation during compilation).
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build

WORKDIR /src

# Copy go.mod first for layer caching — only invalidated when dependencies change.
# This project has no external dependencies so go.sum does not exist.
COPY go.mod ./
RUN go mod download

COPY *.go ./

# ARG TARGETOS and ARG TARGETARCH must be declared after the FROM line.
# BuildKit injects them only after declaration.
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -o /portmux .

# Stage 2: Final image
# FROM scratch — zero OS overhead, only the binary lands in the final image (~5 MB total).
FROM scratch

# Document all 6 ports the binary listens on.
EXPOSE 80 8080 8181 8081 3000 5000

COPY --from=build /portmux /portmux

# Exec-form ENTRYPOINT: process is PID 1 and receives SIGTERM directly.
# Shell-form would fail — FROM scratch has no /bin/sh.
ENTRYPOINT ["/portmux"]
