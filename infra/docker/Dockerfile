# ─────────────────────────────────────────────────────────────────────────────
# SafeVision — Flutter CI Build Image
# Dùng cho: local CI simulation, custom runner, Docker-based testing
# ─────────────────────────────────────────────────────────────────────────────

# Stage 1: Flutter SDK base
FROM ubuntu:24.04 AS flutter-base

ARG FLUTTER_VERSION=3.32.0
ARG FLUTTER_CHANNEL=stable
ARG JAVA_VERSION=17

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV FLUTTER_VERSION=${FLUTTER_VERSION}
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"
ENV PUB_CACHE=/root/.pub-cache

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    wget \
    unzip \
    xz-utils \
    zip \
    ca-certificates \
    gnupg \
    lcov \
    bc \
    openjdk-${JAVA_VERSION}-jdk-headless \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter
RUN git clone \
    --depth 1 \
    --branch ${FLUTTER_VERSION} \
    https://github.com/flutter/flutter.git \
    ${FLUTTER_HOME}

# Pre-warm Flutter (downloads Dart SDK, tools)
RUN flutter config \
        --no-analytics \
        --no-enable-web \
        --no-enable-macos-desktop \
        --no-enable-linux-desktop \
        --no-enable-windows-desktop \
    && flutter precache --android --no-ios \
    && flutter doctor -v

# Stage 2: Project dependencies
FROM flutter-base AS deps

WORKDIR /app

# Copy only dependency files first → layer cache
COPY pubspec.yaml pubspec.lock ./

# Install pub deps (cached unless pubspec.lock changes)
RUN flutter pub get

# Stage 3: Test runner
FROM deps AS test-runner

# Copy project files
COPY . .

# Default: run all tests with coverage
CMD ["flutter", "test", "--coverage", "--reporter=github", "--timeout=60s", "test/"]

# Stage 4: Android build
FROM deps AS android-builder

# Android SDK
ARG ANDROID_SDK_VERSION=commandlinetools-linux-11076708_latest.zip
ARG ANDROID_COMPILE_SDK=36
ARG ANDROID_BUILD_TOOLS=34.0.0

ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && wget -q "https://dl.google.com/android/repository/${ANDROID_SDK_VERSION}" -O /tmp/cmdlinetools.zip \
    && unzip -q /tmp/cmdlinetools.zip -d /tmp/cmdlinetools \
    && mv /tmp/cmdlinetools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm /tmp/cmdlinetools.zip

RUN yes | sdkmanager --licenses \
    && sdkmanager \
        "platform-tools" \
        "platforms;android-${ANDROID_COMPILE_SDK}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" \
        "ndk;27.0.12077973"

COPY . .

CMD ["flutter", "build", "apk", "--release", "--split-per-abi"]
