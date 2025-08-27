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

## Contributions

By invitation only for the time being.

