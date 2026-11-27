FROM rust:1-alpine AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src src
RUN cargo build --release --locked

# 中身はバイナリ 1 つだけ。OS パッケージが無いので image の脆弱性スキャンに引っかからない
FROM scratch
COPY --from=build /src/target/release/status-proxy /status-proxy
USER 65534:65534
EXPOSE 8081
ENTRYPOINT ["/status-proxy"]
