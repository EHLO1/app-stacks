# Multi-stage build to add dependencies to n8n runners
# This works around the issue where n8nio/runners v2.1.0+ removed apk

# Stage 1: Build dependencies in Alpine (must match n8nio/runners base version)
FROM alpine:3.23 AS builder

RUN apk add --no-cache \
    nss \
    ca-certificates \
    openssh-client

# Stage 2: Copy to runners image
FROM n8nio/runners:latest

USER root

# Install npm packages in the task runner's node_modules directory
WORKDIR /opt/runners/task-runner-javascript
RUN /usr/local/bin/node /usr/local/lib/node_modules/corepack/dist/corepack.js pnpm add @keeper-security/secrets-manager-core

# Install Python packages in the task runner's venv
RUN /usr/local/bin/uv pip install --python /opt/runners/task-runner-python/.venv/bin/python --no-cache \
    requests \
    pandas \
    numpy \
    keeper-secrets-manager-core

COPY runner/n8n-task-runners.json /etc/n8n-task-runners.json
RUN chmod 644 /etc/n8n-task-runners.json

USER runner
WORKDIR /home/runner