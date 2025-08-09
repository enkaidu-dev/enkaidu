# Enkaidu

Your trusted second-in-command (line tool) for coding and creativity. Inspired by Enkidu, the loyal and dynamic companion from Mesopotamian mythology, Enkaidu embodies collaboration, adaptability, and a touch of chaos to spark innovation. With the use of AI large language models Enkaidu is designed to assist you with writing & maintaining code (and other text-based content).

## Install

> TODO: via package installers

See "Development" section for how to build `enkaidu`

## Usage

### With Ollama

Run `enkaidu -p ollama -m M` with the model `M` you want to use. (Expects the local server to be at `http://localhost:11434`.)

### With Azure OpenAI

Run `enkaidu -p azure_openai` after setting up the following environment variables:

Env var | Description
-----|-----
`AZURE_OPENAI_API_VER` | For example, `2024-02-15-preview`. Use the one suitable for your model.
`AZURE_OPENAI_MODEL` | Defaults to `gpt-4o` if not specified.
`AZURE_OPENAI_ENDPOINT` | For example, `https://X.openai.azure.com` for your deployment `X`. Just the bare endpoint only please!
`AZURE_OPENAI_API_KEY` | The API key for your deployment

## Development

### Dependencies

1. Make sure you have `ops` installed, in one of the following ways:
 - as a gem via `gem install ops_team` or 
 - as a tool via `brew tap nickthecook/crops && brew install ops`
2. If you not using macOS, or a Linux that uses `apt`, please [install Crystal](https://crystal-lang.org/install/)

### Getting started

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


## Contributions

By invitation only for the time being.

