# Build to add dependencies to n8n runners
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