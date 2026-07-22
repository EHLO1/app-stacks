# Arcane
Configuration for deployment of an Arcane Docker stack.

As of July 10th, 2026: I haven't been able to get the Arcane agents working without the local docker socket.
Until the agents can run without the local docker socket (or until I figure it out), there's no point running the main instance behind a socket proxy.