# Enkaidu Development

## Dependencies

1. Make sure you have `ops` installed, in one of the following ways:
 - as a gem via `gem install ops_team` or
 - as a tool via `brew tap nickthecook/crops && brew install ops`
2. If you not using macOS, or a Linux that uses `apt`, please [install Crystal](https://crystal-lang.org/install/)

## Getting started

Command | Description
-----|-----
`ops up` | Gets everything setup including `crystal` via `apt` or `brew` if applicable.
`ops build-debug` or `ops bd` | Make a debug build, with binary in `bin/debug` folder.
`ops build-release` or `ops br` | Make a dreleasebug build, with binary in `bin/release` folder.
`ops lint` | Run `ameba` on the source code
`ops clean` | Remove debug and release build files
`ops wipe` | In addition to cleaning, remove all compiler caches

### Build and run for development

Run `ops run` which will build the debug version and run it afterwards.

### Build to run later

Run `ops build-release` to make a release build in the `bin/release/` folder

Run `ops build-debug` to make a debug build in the `bin/debug/` folder

### Install

Run `ops install` to make a release build and copy the binary to the directory specify by `INSTALL_DIR` environment variable (which defaults to `$HOME/bin`)

## How to ...

### Build standalone Linux binary

We can build [statically linked Crystal apps for Linux](https://crystal-lang.org/reference/1.19/guides/static_linking.html) using Alpine Linux and a container. The following instructions use `podman` but you can do the same with `docker` if you are so inclined.

```sh
podman run --rm -v "$(pwd):/workspace" -w /workspace nogginly/alpine-crystal-nodejs:latest /bin/sh -c "
            set -e
            # Build the web UI
            cd webui && npm i && npm run build && cd ..
            # Create output directory
            mkdir -p bin/release/linux
            # Build the static binary
            SHARDS_BIN_PATH=bin/release/linux shards build enkaidu --release --static"
```

### Verify standalone Linux binary

After building the standalone Linux binary, run it within a different Linux container to check if it works without missing dependencies.

```sh
podman run --rm -it -v $(pwd):/workspace -w /workspace debian:bookworm-slim /bin/sh -c "bin/release/linux/enkaidu"
```

Voila!

## Contributions

By invitation only for the time being.
