# restic
This app is intended to be used as a sidecar on an existing application stack.

Ensure all services contain a dependency on the restic sidecar:

```yaml
depends_on:
  restic:
    condition: service_healthy
```

This will ensure that restic has completed initialization steps and that data is available prior to application stack startup.

Initialization Logic:
| Local data | Bucket data | Action                                                 |
| ---------- | ----------- | ------------------------------------------------------ |
| Empty      | Present     | Restore S3 → local                                     |
| Empty      | Empty       | Initialize empty stack                                 |
| Present    | Empty       | Adopt existing local data, send snapshot to S3         |
| Present    | Present     | Refuse startup because the correct source is ambiguous |

</br>
The first local → S3 snapshot is performed before marking the container healthy. That ensures an existing stack’s bucket is populated before dependent services start.<br/><br/>

If S3 target is unreachable, authentication fails, or the bucket cannot be inspected, initialization stops instead of adopting local data under a false assumption.<br/><br/>

**!! THIS IS NOT INTENDED FOR USE WITH DATABASE VOLUMES !!**  
Check out Databasus for that!