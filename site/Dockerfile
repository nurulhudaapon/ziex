FROM alpine:3.22.2 AS build

# Setup Zig
ARG ZIG_VER=0.15.2
RUN apk add --no-cache curl xz
RUN curl https://ziglang.org/download/${ZIG_VER}/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz -o zig.tar.xz && \
tar xf zig.tar.xz && \
mv zig-$(uname -m)-linux-${ZIG_VER}/ /opt/zig

# Build the app
WORKDIR /build

COPY src/ ./src
COPY site/ ./site
COPY build.zig.zon ./build.zig.zon
COPY build.zig ./build.zig
RUN /opt/zig/zig fetch --save git+https://github.com/tree-sitter/zig-tree-sitter#a53dac49d66562006e84dd11211b7ae40db68263 

COPY tree-sitter-zx ./tree-sitter-zx

RUN /opt/zig/zig build -Dzx-docsite -Doptimize=ReleaseSmall

# Run the app
FROM alpine:3.22.2
COPY --from=build /build/zig-out/bin/zx_site /server
#COPY --from=build /build/tree-sitter-zx cle
COPY --from=build /build/site/.zx/public /site/.zx/public
COPY --from=build /build/site/.zx/assets /site/.zx/assets
COPY site/.zx/assets/main.js /site/.zx/assets/main.js

ENTRYPOINT ["/server"]

