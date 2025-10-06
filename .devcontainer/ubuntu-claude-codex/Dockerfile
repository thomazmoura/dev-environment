FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Install Node.js 20.x and Claude/Codex CLIs
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @anthropic-ai/claude-code @openai/codex \
    && npm cache clean --force \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
