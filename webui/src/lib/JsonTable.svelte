<script lang="ts">
  // Renders an arbitrary JSON value as a readable property/value table.
  //   - plain object -> one row per key
  //   - array        -> one row per index
  //   - scalar       -> the value itself (single text line)
  // Composite (array/object) cell values fall back to compact JSON so nested
  // structure is preserved without deep recursion. Meant to be reusable for
  // any JSON payload the UI wants to make human-skimmable.
  let { value }: { value: unknown } = $props();

  type Cell = { key: string; composite: boolean; text: string };

  function is_object(v: unknown): v is Record<string, unknown> {
    return !!v && typeof v === "object" && !Array.isArray(v);
  }

  function to_cell(v: unknown): { composite: boolean; text: string } {
    if (v === null || v === undefined) return { composite: false, text: "—" };
    switch (typeof v) {
      case "string":
        return { composite: false, text: v };
      case "number":
      case "boolean":
        return { composite: false, text: String(v) };
      default:
        try {
          return { composite: true, text: JSON.stringify(v) ?? String(v) };
        } catch {
          // Unserializable (e.g. undefined): degrade gracefully.
          return { composite: true, text: String(v) };
        }
    }
  }

  let rows: Cell[] = $derived.by(() => {
    if (is_object(value)) {
      return Object.entries(value).map(([k, v]) => ({ key: k, ...to_cell(v) }));
    }
    if (Array.isArray(value)) {
      return value.map((v, i) => ({ key: String(i), ...to_cell(v) }));
    }
    return [];
  });

  // Scalar fallback (also covers empty object/array -> empty string).
  let scalar_text = $derived(
    !(is_object(value) || Array.isArray(value)) ? to_cell(value).text : "",
  );
</script>

{#if rows.length > 0}
  <table class="w-full border-collapse text-xs">
    <tbody>
      {#each rows as cell (cell.key)}
        <tr class="border-t border-base-content/10">
          <th
            scope="row"
            class="text-left align-top px-0 py-1.5 pr-4 font-mono font-medium text-base-content/45 whitespace-nowrap"
          >
            {cell.key}
          </th>
          <td class="align-top px-0 py-1.5">
            {#if cell.composite}<span
              class="font-mono text-base-content/70 break-words"
              >{cell.text}</span
            >
            {:else}<span
              class="text-base-content/75 whitespace-pre-wrap break-words"
              >{cell.text}</span
            >{/if}
          </td>
        </tr>
      {/each}
    </tbody>
  </table>
{:else if scalar_text}
  <div class="text-xs text-base-content/75 whitespace-pre-wrap break-words">{
    scalar_text
  }</div>
{:else}
  <span class="text-xs text-base-content/30">no parameters</span>
{/if}
