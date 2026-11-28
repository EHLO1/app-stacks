FROM python:3.13-alpine

RUN addgroup -S collector && adduser -S -G collector collector \
    && mkdir -p /app /state && chown collector:collector /state
COPY --chown=collector:collector netbird-access-logs.py /app/collector.py
USER collector
ENTRYPOINT ["python", "-u", "/app/collector.py"]