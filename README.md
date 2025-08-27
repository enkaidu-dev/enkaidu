# Enkaidu

Enkaidu is your _second-in-command(-line)_ for coding and creativity. Inspired by Enkidu, the loyal and dynamic companion from Mesopotamian mythology, Enkaidu embodies collaboration, adaptability, and a touch of chaos to spark innovation.

Out of the box, with the use of _your preferred_ AI large language models, Enkaidu is designed to assist you with writing & maintaining code (and other text-based content). 

Additionally, by integrating with MCP servers _of your choice_, Enkaidu can help you do even more.

## Install

> COMING SOON: pre-built binaries

See [DEVELOPMENT](./DEVELOPMENT.md) for how to build and run `enkaidu`.

Following sections assume you have _installed_ Enkaidu and that it is available to run from anywhere using the `enkaidu` command.

## Get Started

### Start with Ollama

If you have Ollama running, create a file `enkaidu.yaml` and copy in the following configuration, then run `enkaidu` from the commandline in the same folder as the config file.

<details>
<summary>Simple Ollama configuration for `enkaidu`.</summary>

```yaml
session:
  model: qwen3                # <---
  auto_load:
    toolsets:
      - DateAndTime
llms:
  my_ollama:
    provider: ollama
    models:
      - name: qwen3           # <---
        model: qwen3:8b       # <---
```

If you're using a different local model, change the values pointed to by the `# <---` comment
</details>


### Start with LMStudio

If you have LMStudio running, create a file `enkaidu.yaml` and copy in the following configuration, then run `enkaidu` from the commandline in the same folder as the config file.

<details>
<summary>Simple LMStudio configuration for `enkaidu`.</summary>

```yaml
session:
  model: qwen3                       # <---
  auto_load:
    toolsets:
      - DateAndTime
llms:
  my_lmstudio:
    provider: openai
    env:
      OPENAI_ENDPOINT: 'http://localhost:1234'
      OPENAI_API_KEY: n/a
    models:
      - name: qwen3                 # <---
        model: qwen/qwen3-4b        # <---
```

If you're using a different local model, change the values pointed to by the `# <---` comment
</details>


### Start with Chat GPT

If you have an OpenAI Chat GPT account, create a file `enkaidu.yaml` and copy in the following configuration, then run `enkaidu` from the commandline in the same folder as the config file.

<details>
<summary>Simple OpenAI Chat GPT configuration for `enkaidu`.</summary>

```yaml
session:
  model: gpt4
  auto_load:
    toolsets:
      - DateAndTime
llms:
  my_openai:
    provider: openai
    models:
      - name: gpt4
        model: gpt-4.1-2025-04-14
```

Make sure you have `OPENAI_API_KEY` environment variable set. 
</details>

## Understanding LLM Providers

Enkaidu supports the following LLM provider types:
- `azure_openai`
- `ollama`
- `openai`

Each of the providers, when selected for a session, expect different environment variables to specify the connection information.

### Provider: `ollama`

Assuming you're running `ollama serve` locally, the defaults should just work. In case you're not:

<details>
<summary>Environment variables to use with `ollama`</summary>

Env var | Description
----|----
`OLLAMA_ENDPOINT` | Defaults to `http://localhost:1234`
</details>

### Provider: `openai`

The `openai` provider defaults to the Open AI endpoint, but you still need to supply the API KEY.

You can use this provider with different LLM systems who provide an Open AI-compatible API, in which case you'll need to set the environment variables.

<details>
<summary>Environment variables to use with `openai`</summary>

Env var | Description
----|----
`OPENAI_ENDPOINT` | For example, `http://localhost:1234` for LM Studio; defaults to `https://api.openai.com`.
`OPENAI_MODEL` | For example, `gpt-oss:20b`.
</details>

### Provider: `azure_openai`

Azure OpenAI needs many parameters to select the model to use, so you have to set all of these. 

<details>
<summary>Environment variables to use with `azure_openai`</summary>

Env var | Description
-----|-----
`AZURE_OPENAI_API_VER` | For example, `2024-02-15-preview`. Use the one suitable for your model.
`AZURE_OPENAI_MODEL` | Defaults to `gpt-4o` if not specified.
`AZURE_OPENAI_ENDPOINT` | For example, `https://X.openai.azure.com` for your deployment `X`. Just the bare endpoint only please!
`AZURE_OPENAI_API_KEY` | The API key for your deployment
</details>

## Configuration

> Documentation coming soon

## Contributions

By invitation only limited to people I know and see often. This is early days, I am busy with family and work, and this will help me manage my bandwidth.
