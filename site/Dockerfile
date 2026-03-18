FROM alpine:3.22.2 AS build

# Install deps for Zig and Bun
RUN apk add --no-cache curl xz unzip bash libstdc++ libgcc nodejs

# Install Zig
ARG ZIG_VER=0.15.2
RUN curl https://ziglang.org/download/${ZIG_VER}/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz -o zig.tar.xz && \
tar xf zig.tar.xz && \
mv zig-$(uname -m)-linux-${ZIG_VER}/ /opt/zig
ENV PATH="/opt/zig:$PATH"

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Build the app
WORKDIR /build

# Zig Deps
COPY build.zig build.zig.zon ./
RUN zig build --fetch

# Node Deps
COPY site/package.json site/bun.lock ./site/
RUN bun install --cwd ./site

# Ziex Exe
COPY src ./src
COPY vendor ./vendor
COPY pkg ./pkg

# Ziex Site
COPY site/build.zig site/build.zig.zon ./site/
RUN cd site && zig build --fetch
RUN cd site && zig build zx -- version

COPY site/app ./site/app
RUN cd site && zig build -Doptimize=ReleaseSmall -Dtarget=$(uname -m)-linux-musl
RUN cd site && zig build zx -- bundle

# Run Ziex Site
FROM scratch
WORKDIR /app
COPY --from=build /build/site/bundle /app
ENTRYPOINT ["/app/ziex_dev", "--rootdir", "/app"]