FROM golang:1.26-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/luntan-api ./cmd/api
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/luntan-worker ./cmd/worker
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/luntan-migrate ./cmd/migrate

FROM alpine:3.22
RUN addgroup -S luntan && adduser -S -G luntan luntan
WORKDIR /app
COPY --from=builder /out/luntan-api /app/luntan-api
COPY --from=builder /out/luntan-worker /app/luntan-worker
COPY --from=builder /out/luntan-migrate /app/luntan-migrate
COPY migrations /app/migrations
USER luntan
EXPOSE 8080
ENTRYPOINT ["/app/luntan-api"]
