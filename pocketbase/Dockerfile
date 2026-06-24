# Builds a container image that runs the MICHWAR PocketBase backend
# (collections/migrations from pb_migrations/, business logic from pb_hooks/).
#
# Usage (Fly.io): see ../DEPLOYMENT.md "Fly.io (free)" section.
# Usage (any Docker host):
#   docker build -t michwar-pb .
#   docker run -p 8090:8090 -v pb_data:/pb/pb_data michwar-pb

# --- Stage 1: fetch the PocketBase binary -----------------------------------
FROM alpine:3.20 AS builder

# Update this to the latest PocketBase release (https://github.com/pocketbase/pocketbase/releases)
# if you want a newer server version. v0.23.x is the version this app's
# pb_migrations/pb_hooks were written against.
ARG PB_VERSION=0.23.12

RUN apk add --no-cache unzip curl ca-certificates \
    && curl -fsSL "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip" -o /tmp/pb.zip \
    && unzip /tmp/pb.zip -d /pb \
    && rm /tmp/pb.zip

# --- Stage 2: minimal runtime image ------------------------------------------
FROM alpine:3.20

RUN apk add --no-cache ca-certificates

WORKDIR /pb

COPY --from=builder /pb/pocketbase /pb/pocketbase
COPY pb_migrations ./pb_migrations
COPY pb_hooks ./pb_hooks

# Data (SQLite DB + uploaded files) lives here — mount a persistent
# volume at this path in production so it survives redeploys.
VOLUME /pb/pb_data

EXPOSE 8090

CMD ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090"]
