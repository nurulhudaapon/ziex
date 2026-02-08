FROM alpine:3.22.2 AS build

# Install dependencies for Zig and Bun
RUN apk add --no-cache curl xz unzip bash libstdc++ libgcc

# Setup Zig
ARG ZIG_VER=0.15.2
RUN curl https://ziglang.org/download/${ZIG_VER}/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz -o zig.tar.xz && \
tar xf zig.tar.xz && \
mv zig-$(uname -m)-linux-${ZIG_VER}/ /opt/zig

RUN curl -fsSL https://bun.sh/install | bash

# Build the app
WORKDIR /build

COPY src/ ./src
COPY site/ ./site
COPY build.zig.zon ./build.zig.zon
COPY build.zig ./build.zig
COPY pkg/ ./pkg/
COPY vendor/ ./vendor

RUN (cd site && $HOME/.bun/bin/bun install)
RUN /opt/zig/zig build -Ddoc -Doptimize=ReleaseSafe
RUN /opt/zig/zig build -Ddoc -Doptimize=ReleaseSafe zx -- bundle

# Run the app
FROM alpine:3.22.2

COPY --from=build /build/zig-out/bin/zx_site /app/zx_site
COPY --from=build /build/bundle/public /app/public
COPY --from=build /build/bundle/assets /app/assets

ENTRYPOINT ["/app/zx_site", "--rootdir", "./app"]