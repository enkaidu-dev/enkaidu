import "@testing-library/jest-dom/vitest";

// jsdom does not implement several APIs used by the UI, so provide the small
// no-op shims needed to import components without a real browser.
if (typeof globalThis.crypto?.randomUUID !== "function") {
  let counter = 0;
  globalThis.crypto = globalThis.crypto ?? ({} as Crypto);
  globalThis.crypto.randomUUID = (() => `test-uuid-${++counter}`) as () => `${string}-${string}-${string}-${string}-${string}`;
}

if (typeof globalThis.ResizeObserver === "undefined") {
  globalThis.ResizeObserver = class ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver;
}

if (typeof globalThis.matchMedia === "undefined") {
  globalThis.matchMedia = (query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }) as unknown as MediaQueryList;
}

if (typeof globalThis.requestAnimationFrame === "undefined") {
  globalThis.requestAnimationFrame = (cb: FrameRequestCallback) =>
    setTimeout(() => cb(Date.now()), 0);
  globalThis.cancelAnimationFrame = (id: number) => clearTimeout(id);
}
