# Enkaidu Container Image
#
# Enkaidu is your _second-in-command(-line)_ for coding and creativity.
# Inspired by Enkidu, the loyal and dynamic companion from Mesopotamian mythology,
# Enkaidu embodies collaboration, adaptability, and a touch of chaos to spark innovation.
#
# This Containerfile builds Enkaidu as a standalone Linux binary container image.
# The same commands work with Docker instead of Podman if preferred.
#
# To build the container image:
#   podman build -f Containerfile -t enkaidu-for-devs
#
# To run Enkaidu via container with host networking:
#   podman run --rm -it --add-host=<HOSTNAME>.local:host-gateway \
#     -v $(pwd):/workspace -w /workspace localhost/enkaidu-for-devs
#
# The --add-host flag allows using your host name in Enkaidu config files
# when referring to local LLM servers, avoiding the need to use 'localhost'.
# This makes config files portable between host and container execution.
#
# To run Enkaidu in web UI mode:
#   podman run --rm -it --add-host=kotinga.local:host-gateway \
#     -p 8765:8765/tcp -v $(pwd):/workspace -w /workspace \
#     localhost/enkaidu-for-devs --webui
#
FROM nogginly/alpine-crystal-nodejs:latest AS builder

# Copy the entire project into the container
COPY src /workspace/src
COPY webui /workspace/webui
COPY shard* /workspace/

# Ensure we're in the workspace directory before building
WORKDIR /workspace

# Create output directory
RUN mkdir -p bin/release/linux

# Build the web UI
RUN cd webui && npm i && npm run build && cd ..

# Build the static binary
RUN SHARDS_BIN_PATH=bin/release/linux shards build enkaidu --release --static

# Final image based on Alpine Linux
FROM ubuntu:noble AS final

LABEL name="enkaidu"
LABEL description="Run Enkaidu, a command line AI assistant for local models, from within a container. "
LABEL version="<REPLACE_VERSION>"

# Copy the built binary from the builder stage
COPY --from=builder /workspace/bin/release/linux/enkaidu /usr/bin/enkaidu

# Set the entrypoint or default command
ENTRYPOINT ["/usr/bin/enkaidu"]

# Add a user for better security
RUN useradd --create-home --shell /bin/bash enkaidu-user
USER enkaidu-user
ENV ENKAIDU_BIND_TO_ALL=1
