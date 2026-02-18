FROM alpine:3.22.2 AS build

# Setup Zig
ARG ZIG_VER=0.15.2
RUN apk add --no-cache curl xz
RUN curl https://ziglang.org/download/${ZIG_VER}/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz -o zig.tar.xz && \
tar xf zig.tar.xz && \
mv zig-$(uname -m)-linux-${ZIG_VER}/ /opt/zig
ENV PATH="/opt/zig:$PATH"

# Build the app
WORKDIR /build

## Install Zig dependencies
COPY build.zig build.zig.zon ./
RUN zig build --fetch

## Copy source files
COPY ./bench/ziex/ ./bench/ziex/
COPY src/ ./src/
COPY vendor/ ./vendor/
COPY pkg/ pkg/

RUN cd bench/ziex && zig build -Doptimize=ReleaseFast
RUN cd bench/ziex &&  zig build zx -- bundle

# Run the app
FROM alpine:3.22.2

# Install curl for health checks
RUN apk add --no-cache curl
COPY --from=build /build/bench/ziex/bundle /app

ENTRYPOINT ["/app/zx_bench_client", "--rootdir", "./app"]