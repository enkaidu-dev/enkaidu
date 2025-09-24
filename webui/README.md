
# Enkaidu Web UI

This is the Svelte-based web UI for Enkaidu's server mode.

> Work in progress

This will be _baked_ into the Enkaidu binary and available to the user via browser in server mode.


## Baseline

- Use `vite` to create an empty `svelte-ts` project. This is ideal for client-side web UI dev since the backend is going to be our Crystal app
- Use daisyUI + Tailwinds CSS to handle the UX design
- Use Svelte to build a client-side app with components

## References

### Crystal

1. Use HTTP::Server (see src/sucre/api_server)
2. [Baked file system](https://github.com/schovi/baked_file_system) for embedding the web UI "dist" into the app's single binary.

### Web UI

1. Vite ([docs](https://vite.dev/guide/))
1. Svelte ([home](https://svelte.dev/))
1. Svelte [Tutorial](https://svelte.dev/tutorial/svelte/welcome-to-svelte)
1. TailwindCSS ([docs(https://tailwindcss.com/docs/styling-with-utility-classes)])
1. daisy UI ([docs](https://daisyui.com/docs/intro/))
