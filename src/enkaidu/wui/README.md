# Web UI for Crystal App

This example is an attempt to build a CLI app that publishes a web UI as well, presenting either a TUI or GUI based on user preference.

## So far

- Use `vite` to create an empty `svelte-ts` project. This is ideal for client-side web UI dev since the backend is going to be our Crystal app
- Use daisyUI + Tailwinds CSS to handle the UX design
- Use Svelte to build a client-side app with components

## To do

- Treat the app as an API server so Svelte can call the app to get data?
- Use Kemal to expose private routes to fetch data from the app?
- How to "push" alerts from Crysal app "into" web UI?

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
