FROM thomazmoura/dev-environment:latest

USER root

# Ensure Node.js 20.x and Claude/Codex CLIs are available system-wide
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @anthropic-ai/claude-code @openai/codex \
    && npm cache clean --force \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER developer

ENV PATH="/usr/local/bin:/usr/bin:/bin:/home/developer/.local/bin"
