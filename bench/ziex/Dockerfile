FROM alpine:3.22.2 AS build

# Setup Zig
ARG ZIG_VER=0.15.2
RUN apk add --no-cache curl xz
RUN curl https://ziglang.org/download/${ZIG_VER}/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz -o zig.tar.xz && \
tar xf zig.tar.xz && \
mv zig-$(uname -m)-linux-${ZIG_VER}/ /opt/zig

# Build the app
WORKDIR /build
COPY ./bench/ziex/ ./bench/ziex/
COPY src/ ./src/
COPY vendor/ ./vendor/
COPY pkg/ pkg/
COPY build.zig.zon build.zig.zon
COPY build.zig build.zig
RUN cd bench/ziex && /opt/zig/zig build -Doptimize=ReleaseFast

# Run the app
FROM alpine:3.22.2

# Install curl for health checks
RUN apk add --no-cache curl

COPY --from=build /build/bench/ziex/zig-out/bin/zx_bench_client /app/zx_bench_client

WORKDIR /app
EXPOSE 3000

ENTRYPOINT ["/app/zx_bench_client"]
