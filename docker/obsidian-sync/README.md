# Obsidian Self-Hosted LiveSync

See: https://github.com/vrtmrz/obsidian-livesync

_This doc assumes use of Cloudflare and a Cloudflare tunnel for service routing._

### Upon completion of deploying this stack (CouchDB), complete the following steps:<br/>

1. Create a 'Published application route' in Cloudflare<br/><br/>
2. On a linux-based host, run the following, ensuring to replace the hostname, username, and password values accordingly:<br/><br/>
   ```shell
   curl -s https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/main/utils/couchdb/couchdb-init.sh | hostname=${OBSIDIAN_SYNC_URL:-https://obsync.example.com} username=${COUCHDB_USER:-obsidiansync} password=${COUCHDB_PASSWORD:-supergreatpassword} bash
   ```
   <br/>
3. To avoid needing to install deno, run the following script in a deno docker container:
   ```shell
   docker run --rm -it \
    -e hostname="${OBSIDIAN_SYNC_URL:-https://obsync.example.com}" \
    -e database="${OBSIDIAN_SYNC_DB_NAME:-obsidian}" \
    -e username="${COUCHDB_USER:-obsidiansync}" \
    -e password="${COUCHDB_PASSWORD:-supergreatpassword}" \
    -e passphrase=${OBSIDIAN_SYNC_E2EE_PASSPHRASE:-supergreate2eepassphrase} \
    denoland/deno:alpine run --allow-net --allow-env \
    https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/main/utils/flyio/generate_setupuri.ts
   ```
   <br/>
4. You will then get the following output:<br/>
   ```
   obsidian://setuplivesync?settings=%5B%22tm2DpsOE74nJAryprZO2M93wF%2Fvg.......4b26ed33230729%22%5D

    Your passphrase of Setup-URI is:  patient-haze
    This passphrase is never shown again, so please note it in a safe place.
   ```
5. Use the Setup-URI and passphrase from Step 4. in the Self-Hosted LiveSync plugin in the Obsidian app.
