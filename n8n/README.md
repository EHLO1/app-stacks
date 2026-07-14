# n8n Single Stack
This configuration can be used to deploy a single n8n application stack using Docker Compose.

## Purpose
There are many ways to deploy n8n, but this is a basic, secure, and stable method that will scale generally well (to a point). The goal is to minimize dependencies, while still allowing for strong functionality and flexibility.

## Overview
- n8n main instance, set to queue mode
- n8n worker instance
- n8n task runner for execution of Javascript and Python code in the Code node
- Postgres 17
- Valkey 9
