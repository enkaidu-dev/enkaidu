# Enkaidu

![Enkaidu](./webui/public/favicon.png)

Enkaidu is your _second-in-command(-line)_ for coding and creativity. Inspired by Enkidu, the loyal and dynamic companion from Mesopotamian mythology, Enkaidu embodies collaboration, adaptability, and a touch of chaos to spark innovation.

Out of the box, with the use of _your preferred_ AI large language models, Enkaidu is designed to assist you with writing & maintaining code (and other text-based content).

Additionally, by integrating with MCP servers _of your choice_, Enkaidu can help you do even more.

<!-- TOC -->
- [Install](#install)
- [Get Started](#get-started)
  - [Start with Ollama](#start-with-ollama)
  - [Start with LMStudio](#start-with-lmstudio)
  - [Start with Chat GPT](#start-with-chat-gpt)
- [Understanding LLM Providers](#understanding-llm-providers)
  - [Provider: `ollama`](#provider-ollama)
  - [Provider: `openai`](#provider-openai)
  - [Provider: `azure_openai`](#provider-azure_openai)
- [Usage](#usage)
  - [User Queries](#user-queries)
  - [Slash Commands](#slash-commands)
  - [Advanced Usage](#advanced-usage)
- [Configuration](#configuration)
  - [Overview of Configuration Sections](#overview-of-configuration-sections)
  - [Structure of the Configuration File](#structure-of-the-configuration-file)
  - [Example Configuration](#example-configuration)
- [Profile](#profile)
  - [System Properties](#system-properties)
  - [Variables](#variables)
  - [Arguments](#arguments)
  - [Example](#example)
- [Contributions](#contributions)
  - [By invitation](#by-invitation)
<!-- /TOC -->

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

## Usage

Once Enkaidu is started, you can interact with it using predefined commands and tools. The available commands serve to enhance your productivity by connecting you with MCP servers and leveraging the capabilities of LLMs. Below are some basic commands to get you started:

### User Queries

You can input your queries directly into Enkaidu. If the query is prefixed with `/`, it will be treated as a command. Otherwise, it will be processed as a general query that Enkaidu will handle using the available tools and LLMs.

### Slash Commands

- **`/help`**: Display a list of all available slash commands along with their descriptions.
- **`/bye`**: Exit the Enkaidu application.

#### Session management

- **`/session usage`**: Shows the token usage/size for the current session based on the most recent response from the LLM.
- **`/session save <FILEPATH>`**: Saves the current chat session to a JSONL file. The file should not be edited.
- **`/session load <FILEPATH> [tail=<N>]`**: Loads a saved chat session from its JSONL file, and optionally _tails_ last `N` chats.
- **`/session reset`**: Resets and cleares the current session including tools and MCP connections and starts anew per config.

#### Tools management

- **`/tool ls`**: List all available tools that you can activate.
- **`/tool info <TOOLNAME>`**: Provide detailed information about the specified tool.
- **`/toolset ls`**: List all built-in toolsets available for activation.
- **`/toolset load <TOOLSET_NAME>`**: Load all the tools from the specified toolset.
- **`/toolset unload <TOOLSET_NAME>`**: Unload all the tools from the specified toolset.

#### MCP connections

- **`/use_mcp <NAME|URL>`**: Connect to an MCP server using either a predefined name from your configuration or a direct URL. Optionally, specify authentication and transport settings.

#### Including files

- **`/include image_file <PATH>`**: Include an image from a file with the next query to the AI model.
- **`/include text_file <PATH>`**: Include text from a file with the next query to the AI model.
- **`/include any_file <PATH>`**: Include any supported file with the next query to the AI model.
- **`/include response_json_schema <PATH>`**: Specify a JSON schema description to tell the model that the
        next response should be a JSON object matching the schema.

#### Prompts

- **`/prompt ls`**: List available prompts
- **`/prompt info <NAME>`**: List the details about the specific prompt.
- **`/prompt use <NAME>`**: Use or invoke a prompt by name. If the prompt has arguments, you will be asked to enter values for each one.

### Advanced Usage

You can configure Enkaidu to automatically load specific toolsets and models. This can be set up in the `enkaidu.yaml` configuration file described in the [Get Started](#get-started) section.

Remember to explore and experiment with the commands and configurations to fully leverage the power of Enkaidu in your coding and creative endeavors.

## Macros

Macros are defined with names, and any macro can be run by typing `!<name>` where `<name>` is the name used when defining the macro.

```
QUERY> !test
```

The above example will run a macro named `test`.

## Configuration

Enkaidu utilizes a configuration file to store various settings for its behavior and interaction with Large Language Models (LLMs) and MCP servers. By default, this configuration is specified in a YAML file located at `./enkaidu.yaml` (or `.yml`). Customizing this file allows you to optimize Enkaidu for your environment and needs.

### Overview of Configuration Sections

Below is an overview of the configuration file, detailing the purpose and optionality of each top-level section:

- **global** _(optional)_: Controls application-wide settings, such as debugging and streaming capabilities.

- **session** _(optional)_: Manages user session-specific configurations, including model selection and auto-loading preferences. Some properties within this section are optional.

- **llms** _(optional)_: Specifies configurations related to Large Language Model providers, detailing which models to use and their respective settings.

- **mcp_servers** _(optional)_: Details the configuration for MCP (Multiple Control Protocol) servers, enabling extended functionalities through server connections.

### Structure of the Configuration File

The configuration file is structured in several key sections. Here’s an overview of each section and its properties:

#### Global Settings
- **global**: Configurations applicable to the whole application.
  - **trace_mcp**: Enables tracing of MCP communication, useful for debugging purposes.
  - **streaming**: Indicates whether streaming responses are supported. When disabled (default) the responses are formatted but take time to appear all at once.

#### Session Settings
- **session**: Configurations specific to a user session.
  - **provider_type** _(optional)_: Specifies the type of LLM provider to be used, such as `openai` or `ollama`. You never need this _if_ you define `llms`, in which case you only need **model** property.
  - **model** _(optional)_: Defines the model used for the session, e.g., `gpt4`. When defining `llms` in the configuration, this can be the name of a model and there is no need for the above **provide_type** property.
  - **recording_file** _(optional)_: Path to a file where session recordings are saved.
  - **input_history_file** _(optional)_: Path to a file for saving input history.
  - **system_prompt** _(optional)_: Custom system prompt for the session.
  - **auto_load** _(optional)_: Contains settings for automatically loading specific resources.
    - **mcp_servers** _(optional)_: List of MCP servers to automatically connect to on startup.
    - **toolsets** _(optional)_: List of toolsets to automatically load, where each toolset can be specified by name to load all tools, or as a map of `name:` and `select:` to specify the tools to load from the named toolset.

#### LLM Providers
- **llms**: Defines the configuration for different LLM providers as a named map of LLM definitions where _each_ can have the following properties.
  - **provider**: Type of provider, e.g., `openai`.
  - **models**: List of models supported by the provider, where each has the following properties:
    - **name**: Unique name for the model, which can be used with the **session.model** property.
    - **model**: The name of the model as defined by the provider
  - **env**: Environmental variables specific to the provider, essential for authentication and connection.

#### MCP Servers
- **mcp_servers**: Defines one or more MCP servers as a named map of server definitions where _each_ can have the following properties. These can be auto-loaded (see **session** above) or you can load them using the `/use_mcp` command with the name in the config.
  - **url**: URL endpoint for the MCP server.
  - **transport** _(optional)_: The MCP protocol supports either `http` (modern) or `legacy`; default is `auto` which tries to pick the right one. For quick connectivity specify the transport.
  - **bearer_auth_token** _(optional)_: Token or API key required for authenticated access to the server that supports authentication.

#### Custom Prompts
- **prompts**: Define named custom parametrized prompt templates. These are auto-loaded when Enkaidu starts.
  - **<prompt_name>**:
    - **description**: A description of the prompt
    - **arguments**: This is a named map of aguments:
      - **<arg_name>**:
        - **description**: A description of the argument
    - **template**: The template is a string based on the [Liquid templating language](http://shopify.github.io/liquid/) as implemented by the [`liquid.cr`](https://github.com/amberframework/liquid.cr) Crystal shard. The template is invoked with arguments as well as
  system and profile properties as follows:
      - Arguments are available with the `arg.` prefix
      - Profile variables are available with the `var.` prefix
      - System properties are available via the `sys.` prefix

#### System Prompts
- **system_prompts**: Define named system prompts as templates. These are auto-loaded when Enkaidu starts.
  - **<prompt_name>**:
    - **description**: An optional description of the prompt
    - **template**: The template is a string based on the [Liquid templating language](http://shopify.github.io/liquid/) as implemented by the [`liquid.cr`](https://github.com/amberframework/liquid.cr) Crystal shard. The template is invoked with system and profile properties as follows:
      - Profile variables are available with the `var.` prefix
      - System properties are available via the `sys.` prefix

#### Macros
- **macros**: Defined named macros that can be invoked using `!<name>`
  - **<name>**:
    - **description**: An description of the macro (required)
    - **queries**: An array of queries where each entry is treated as if the user typed in a query.

<details>
<summary>Example of a macro</summary>

```yaml
macros:
  test:
    description: A test macro
    queries:
      - /session push
      - /prompt use test
      - /session pop
```
</details>


### Example Configuration

Here's an example of a typical `enkaidu.yaml` configuration:

```yaml
global:
  streaming: false
session:
  model: gpt4
  auto_load:
    toolsets:
      - DateAndTime
      - name: FileManagement
        select:
          - list_files
llms:
  my_openai:
    provider: openai
    models:
      - name: gpt4
        model: gpt-4.1-2025-04-14
    env:
      OPENAI_API_KEY: your-api-key
mcp_servers:
  gitmcp_ops:
    url: https://gitmcp.io/nickthecook/ops
    transport: http
```

## Profile

A "profile" is defined by setting up `.enkaidu/` in the current directory. Enkaidu will look for this folder from which it loads the following:

1. `enkaidu.yaml|yml` config file, if none exists in the current folder or somewhere else explicitly specified
2. `variables.yaml|yml` file that can be used to define variables accessible by prompt templates under `var.`
    - Values can be strings, arrays of strings
    - Values can also be hash maps, but only one level deep
3. `prompts/` folder inside which Enkaidu will find any file that has `.yaml|yml` extension and attempts to load the prompts definitions, defined the same way as `prompts:` in the config file.
    - Prompts with the same name in the config file will override prompts defined here.
3. `system_prompts/` folder inside which Enkaidu will find any file that has `.yaml|yml` extension and attempts to load system prompt definitions, defined the same way as `system_prompts:` in the config file.
    - System prompts with the same name in the config file will override those defined in the profile.

> MORE TO COME ... the idea is that profiles can be defined in their own repos and then cloned into the working folder, or includes as git submodules as part of the repo.

### System Properties

The following system properties are available to the templates.

Name | Description
----|------
`sys` |
&nbsp;&nbsp;&nbsp;`.os_arch` | OS architecture extracted from the LLVM target tuple
&nbsp;&nbsp;&nbsp;`.os_name` | OS name extracted from the LLVM target tuple

### Variables

Variables defined in `.enkaidu/variables.yaml|yml` are available under `var.` in the template.

### Arguments

Arguments defined by a prompt are available under `arg.` in the template.

### Example

This example hows how a prompt is defined in the config file. In a profile's prompt definition files you don't need to specify `prompts:`.

```yaml
prompts:
  test:
    description: Test variables
    arguments:
      lang:
        description: Type in the name of a programming language.
    template: |
      OS Architecture: {{ sys.os_arch }}
      OS Name: {{ sys.os_name }}
      Language: {{ arg.lang }}
      Values: {{ var.various }}
      What kind of platform am I working on?
```

## Contributions

### By invitation

At this time, contributions are by invitation only and limited to people I know and see often. These are early days for Enkaidu, and I am busy with family and work. At this time I want to work on this at a manage-able pace.
