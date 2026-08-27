# rclone
This app is intended to be used as a sidecar on an existing application stack.

Ensure all services contain a dependency on the rclone sidecar:

```yaml
depends_on:
  rclone:
    condition: service_healthy
```

This will ensure that rclone has completed synchronization and that data is available prior to application stack startup.