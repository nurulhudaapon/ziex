FROM alpine:3.22.2 AS build

# Install Zig
ARG ZIG_VER=0.15.2
RUN apk add --no-cache curl xz
RUN curl https://ziglang.org/download/${ZIG_VER}/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz -o zig.tar.xz && \
tar xf zig.tar.xz && \
mv zig-$(uname -m)-linux-${ZIG_VER}/ /opt/zig
ENV PATH="/opt/zig:$PATH"

# Node/Bun Pre-requisites
# RUN apk add --no-cache unzip bash libstdc++ libgcc nodejs npm

# Install Bun
# RUN curl -fsSL https://bun.sh/install | bash
# ENV PATH="/root/.bun/bin:${PATH}"

# Build the app
WORKDIR /build

# Node.js dependencies (node)
# COPY package.json package-lock.json ./
# RUN npm install

# Node.js dependencies (bun)
# COPY package.json bun.lock ./
# RUN bun install

# Zig Dep
COPY build.zig build.zig.zon ./
RUN zig build --fetch

COPY . .

RUN zig build -Doptimize=ReleaseSafe
RUN zig build zx -- bundle

# Run the app
FROM alpine:3.22.2
COPY --from=build /build/bundle/ /app/
ENTRYPOINT ["/app/$BIN_NAME", "--rootdir", "./app"]
