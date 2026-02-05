# Enkaidu Container Image
#
# 1. Used by Github action to publish image; relies on action to setup shards lib/ and build web UI dist/
# 2. Can be used to build local container images; see DEVELOPMENT.md for how to build
#
FROM crystallang/crystal:latest-alpine AS builder

# Copy the entire project into the container
COPY src /workspace/src
COPY lib /workspace/lib
COPY webui /workspace/webui
COPY shard* /workspace/

# Ensure we're in the workspace directory before building
WORKDIR /workspace

# Build the static binary
RUN shards --production build enkaidu --release --static

# Final image based on Alpine Linux
FROM ubuntu:noble AS final

LABEL name="enkaidu"
LABEL description="Run Enkaidu, a command line AI assistant for local models, from within a container. "

# Copy the built binary from the builder stage
COPY --from=builder /workspace/bin/enkaidu /usr/bin/enkaidu

# Set the entrypoint or default command
ENTRYPOINT ["/usr/bin/enkaidu"]

# Add a user for better security
RUN useradd --create-home --shell /bin/bash enkaidu-user
USER enkaidu-user
ENV ENKAIDU_BIND_TO_ALL=1
