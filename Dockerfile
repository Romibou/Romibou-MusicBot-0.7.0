# syntax=docker/dockerfile:1.12

# Multi-stage build for JMusicBot
# Stage 1: Build the application
FROM maven:3.9.12-eclipse-temurin-25-alpine AS builder

ARG BUILD_TIMESTAMP
ENV BUILD_TIMESTAMP=$BUILD_TIMESTAMP

WORKDIR /build

# Copy pom.xml first for better layer caching
COPY --link pom.xml .

# Download dependencies with BuildKit cache mount for Maven repository
# This significantly speeds up builds by persisting dependencies between builds
RUN --mount=type=cache,target=/root/.m2/repository \
    mvn dependency:go-offline -B -Pdocker

# Copy source code
COPY --link src ./src

# Build the application with BuildKit cache mount
RUN --mount=type=cache,target=/root/.m2/repository \
    if [ -n "$BUILD_TIMESTAMP" ]; then \
      mvn clean package -DskipTests -B -Pdocker -Dproject.build.outputTimestamp="$BUILD_TIMESTAMP"; \
    else \
      mvn clean package -DskipTests -B -Pdocker; \
    fi


# Stage 2: Create custom minimal JRE using jlink
# Using noble (Ubuntu 24.04) for glibc 2.39 compatibility with native libraries
FROM eclipse-temurin:25-jdk-noble AS jre-builder

# Create a minimal JRE with only the modules JMusicBot needs
# Modules determined by: jdeps --print-module-deps --ignore-missing-deps <jar>
# Plus runtime-loaded modules that jdeps can't detect:
#   java.base         - Core Java classes
#   java.compiler     - Annotation processing (used by some libraries)
#   java.desktop      - GUI support (Swing/AWT, even for headless mode)
#   java.logging      - SLF4J/Logback logging
#   java.naming       - JNDI (required by Logback)
#   java.net.http     - HTTP client API
#   java.scripting    - ScriptEngine for EvalCmd (Rhino)
#   java.security.jgss - Kerberos/GSS-API security
#   java.sql          - JDBC (used by some dependencies)
#   jdk.crypto.ec     - Elliptic curve crypto for TLS/SSL (Discord API) - runtime loaded
#   jdk.management    - JMX management extensions
#   jdk.unsupported   - Native library access (jdave, udpqueue)
RUN $JAVA_HOME/bin/jlink \
    --add-modules java.base,java.compiler,java.desktop,java.logging,java.naming,java.net.http,java.scripting,java.security.jgss,java.sql,jdk.crypto.ec,jdk.httpserver,jdk.management,jdk.unsupported \
    --strip-debug \
    --no-man-pages \
    --no-header-files \
    --compress=zip-6 \
    --output /javaruntime


# Stage 3: Runtime image
# Using Bitnami minideb:trixie (Debian 13) for minimal size with glibc 2.41
# Required for jdave/udpqueue native libraries which need glibc >= 2.38
FROM bitnami/minideb:trixie

# OCI image labels for better traceability and management
LABEL org.opencontainers.image.title="JMusicBot" \
      org.opencontainers.image.description="A cross-platform Discord music bot with a clean interface" \
      org.opencontainers.image.url="https://jmusicbot.com" \
      org.opencontainers.image.source="https://github.com/arif-banai/MusicBot" \
      org.opencontainers.image.vendor="JMusicBot" \
      org.opencontainers.image.licenses="Apache-2.0"

# Copy custom JRE from jre-builder stage
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"
COPY --from=jre-builder /javaruntime $JAVA_HOME

# Cloudflare WARP tools (see docker/warp-proxy.sh): wgcf registers a free WARP
# device, wireproxy exposes the WireGuard tunnel as a local HTTP proxy.
# Pinned versions, verified against the SHA-256 published on their GitHub releases.
ARG WGCF_VERSION=2.3.1
ARG WGCF_SHA256=4fb7a136aa470ece11d17949c7db07b040ec9c604742dc8680bcf1889f85d0c8
ARG WIREPROXY_VERSION=1.1.3
ARG WIREPROXY_SHA256=e88c1d090740373fc606c1bafd81d9a5eadc642cce5667616e20e9d7a444f51c
RUN install_packages curl ca-certificates && \
    curl -fsSL -o /usr/local/bin/wgcf \
      "https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_${WGCF_VERSION}_linux_amd64" && \
    echo "${WGCF_SHA256}  /usr/local/bin/wgcf" | sha256sum -c - && \
    curl -fsSL -o /tmp/wireproxy.tar.gz \
      "https://github.com/windtf/wireproxy/releases/download/v${WIREPROXY_VERSION}/wireproxy_linux_amd64.tar.gz" && \
    echo "${WIREPROXY_SHA256}  /tmp/wireproxy.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/wireproxy.tar.gz -C /usr/local/bin wireproxy && \
    rm /tmp/wireproxy.tar.gz && \
    chmod 755 /usr/local/bin/wgcf /usr/local/bin/wireproxy

# Create non-root user and application directories in single layer
RUN groupadd --gid 10001 jmusicbot && \
    useradd --uid 10001 --gid 10001 --shell /bin/false jmusicbot && \
    mkdir -p /app /musicbot && \
    chown -R jmusicbot:jmusicbot /app /musicbot

# Copy the built JAR from builder stage
COPY --from=builder --chown=jmusicbot:jmusicbot /build/target/JMusicBot-*-All.jar /app/app.jar

# Copy and set permissions for entrypoint script
COPY --chown=jmusicbot:jmusicbot --chmod=755 docker/entrypoint.sh /app/entrypoint.sh
COPY --chown=jmusicbot:jmusicbot --chmod=755 docker/warp-proxy.sh /app/warp-proxy.sh

# Copy config.txt (env-var placeholders only, no secrets) into the working directory
COPY --chown=jmusicbot:jmusicbot config.txt /musicbot/config.txt

WORKDIR /musicbot

# Switch to non-root user for security
USER jmusicbot

ENTRYPOINT ["/app/entrypoint.sh"]
