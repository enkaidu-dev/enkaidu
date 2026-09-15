export type PromptHistoryEntry = {
  text: string;
  timestamp: number;
  id: string;
};

export type PromptHistoryOptions = {
  maxSize?: number;
};

export class PromptHistory {
  entries: PromptHistoryEntry[] = [];
  private _index: number = -1;
  private _previewBuffer: string | null = null;
  private readonly maxSize: number;

  constructor(opts: PromptHistoryOptions = {}) {
    this.maxSize = opts.maxSize ?? 100;
  }

  async loadFromServer(): Promise<void> {
    try {
      const res = await fetch("/api/prompt_history", { method: "GET" });
      if (!res.ok) return;
      const data: string[] = await res.json();
      this.entries = data
        .map((text) => ({
          text,
          timestamp: Date.now(),
          id: crypto.randomUUID?.() ?? String(Date.now()),
        }));
      // keep maxSize
      if (this.entries.length > this.maxSize) {
        this.entries = this.entries.slice(-this.maxSize);
      }
    } catch { }
  }

  async syncToServer(texts: string[]): Promise<void> {
    if (!texts.length) return;
    try {
      await fetch("/api/prompt_history", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(texts),
      });
    } catch { }
  }

  push(text: string): void {
    const trimmed = text.trim();
    if (!trimmed) return;
    // emulate server dedup: move existing occurrence to bottom
    const existingIdx = this.entries.findIndex((e) => e.text === trimmed);
    if (existingIdx !== -1) {
      this.entries.splice(existingIdx, 1);
    }
    const entry: PromptHistoryEntry = {
      text: trimmed,
      timestamp: Date.now(),
      id: crypto.randomUUID?.() ?? String(Date.now()),
    };
    this.entries.push(entry);
    if (this.entries.length > this.maxSize) {
      this.entries = this.entries.slice(-this.maxSize);
    }
    this._index = -1;
    this._previewBuffer = null;
  }

  /** Move to previous entry, returns text. Pass current draft to store preview on first navigation */
  previous(currentDraft?: string): string | null {
    if (this.entries.length === 0) return null;
    if (this._index === -1) {
      this._previewBuffer = currentDraft ?? "";
      this._index = this.entries.length - 1;
    } else if (this._index > 0) {
      this._index--;
    }
    return this.entries[this._index]?.text ?? null;
  }

  /** Move to next entry, returns text */
  next(): string | null {
    if (this.entries.length === 0) return null;
    if (this._index === -1) {
      return this._previewBuffer ?? "";
    }
    this._index++;
    if (this._index >= this.entries.length) {
      this._index = -1;
      return this._previewBuffer ?? "";
    }
    return this.entries[this._index]?.text ?? null;
  }

  get entriesSnapshot(): readonly PromptHistoryEntry[] {
    return this.entries;
  }

  clear(): void {
    this.entries = [];
    this._index = -1;
    this._previewBuffer = null;
  }
}
