# Build image
FROM swift:5.10-jammy AS build
WORKDIR /build
COPY Package.* ./
RUN swift package resolve
COPY Sources ./Sources
COPY Tests ./Tests
RUN swift build -c release --static-swift-stdlib

# Runtime image
FROM ubuntu:jammy
RUN apt-get update -q && apt-get install -y --no-install-recommends \
    ca-certificates tzdata libcurl4 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /build/.build/release/App /app/App
ENV MIDWAY_DB_PATH=/data/midway.sqlite
EXPOSE 8080
ENTRYPOINT ["/app/App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
