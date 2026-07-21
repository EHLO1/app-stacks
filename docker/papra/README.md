# Papra DMS
There are a lot of configuration options: https://docs.papra.app/self-hosting/configuration/#configuration-variables
- PROCESS_MODE allows running instances of web and worker separately
- DOCUMENT_STORAGE_DRIVER allows "filesystem" or "s3" for document storage
- CONTENT_EXTRACTION_STRATEGY allows for AI and or other OCR/parsing methods (default is fine to start)
- Multiple configuration settings to allow ingest via email using OwlRelay or Cloudflare Email Workers
- AI_IS_ENABLED AI Features