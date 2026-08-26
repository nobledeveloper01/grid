# The Grid server: tenant statements, and the page a tenant opens.
#
# Unlike the app's Dockerfile one directory up, there is nothing awkward here.
# Go cross-compiles, the binary has no runtime dependencies, and the final
# image is a scratch layer holding one static file. It builds natively on
# whatever architecture the host has.
FROM golang:1.26-alpine AS build

WORKDIR /src

# Dependencies first so a source edit does not re-resolve the module graph.
# This project has none beyond the standard library, which is deliberate: a
# statement page that renders on a 3G connection has no business pulling a
# framework, and every dependency is a supply-chain surface on a service that
# holds people's bills.
COPY go.mod ./
RUN go mod download

COPY . .

# Vet and test as build steps, so a failure fails the image rather than
# printing into a log nobody reads.
RUN go vet ./...
RUN go test ./...

# Static, stripped, reproducible. CGO off so the result runs on scratch.
RUN CGO_ENABLED=0 go build \
      -trimpath \
      -ldflags='-s -w' \
      -o /out/gridserver ./cmd/gridserver

FROM scratch AS server

# The binary talks TLS to nothing today, but it will the moment a webhook or a
# push provider arrives, and discovering the missing roots then is worse than
# carrying 200 KB now.
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /out/gridserver /gridserver

# Nobody, explicitly. A statement server has no reason to be root and scratch
# gives no shell to fall back on if it were compromised.
USER 65534:65534

EXPOSE 8080
ENTRYPOINT ["/gridserver"]
