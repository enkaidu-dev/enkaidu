<script lang="ts" module>
  // Robust, zero-dependency RFC-4180 CSV parser
  export function parse_csv(text: string): string[][] {
    const lines: string[][] = [];
    let row: string[] = [];
    let curr = "";
    let inQuotes = false;
    
    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      const nextChar = text[i + 1];
      
      if (inQuotes) {
        if (char === '"') {
          if (nextChar === '"') {
            curr += '"';
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          curr += char;
        }
      } else {
        if (char === '"') {
          inQuotes = true;
        } else if (char === ',') {
          row.push(curr);
          curr = "";
        } else if (char === '\n' || char === '\r') {
          row.push(curr);
          curr = "";
          if (row.length > 0 || (char === '\n' && lines.length > 0)) {
            lines.push(row);
          }
          row = [];
          if (char === '\r' && nextChar === '\n') {
            i++;
          }
        } else {
          curr += char;
        }
      }
    }
    
    if (curr || row.length > 0) {
      row.push(curr);
      lines.push(row);
    }
    
    return lines;
  }
  
  // Renders a high-fidelity static HTML table directly for streaming placeholders
  export function render_csv_to_html(source: string): string {
    const parsed = parse_csv(source);
    if (parsed.length === 0) return '<div class="p-3 text-xs text-base-content/45">Empty CSV</div>';
    
    const headers = parsed[0];
    const rows = parsed.slice(1);
    
    let html = '<div class="overflow-x-auto max-h-[352px] overflow-y-auto w-full p-2">' +
               '<table class="table table-zebra table-xs table-pin-rows w-full border-collapse text-left text-xs">';
    
    // Header
    html += '<thead><tr class="bg-base-300">';
    for (const h of headers) {
      const esc = h.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
      html += `<th class="px-3 py-1.5 border border-base-300 font-bold bg-base-200">${esc}</th>`;
    }
    html += '</tr></thead>';
    
    // Body
    html += '<tbody>';
    for (const r of rows) {
      html += '<tr class="border-t border-base-content/10">';
      for (let j = 0; j < headers.length; j++) {
        const val = r[j] ?? '';
        const esc = val.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        html += `<td class="px-3 py-1.5 border border-base-300 whitespace-nowrap text-base-content/85">${esc}</td>`;
      }
      html += '</tr>';
    }
    html += '</tbody></table></div>';
    return html;
  }
</script>

<script lang="ts">
  import BlockFrame from "./BlockFrame.svelte";

  let { source, language }: { source: string; language: string } = $props();
  let view = $state<"diagram" | "code">("diagram");

  let parsed = $derived(parse_csv(source));
  let headers = $derived(parsed[0] ?? []);
  let rows = $derived(parsed.slice(1));
</script>

<BlockFrame {language} {source} rendered={true} failed={parsed.length === 0} error="No data" diagramLabel="Table" codeLabel="Raw" bind:view>
  {#if parsed.length > 0}
    <div class="overflow-x-auto max-h-[352px] overflow-y-auto w-full p-2">
      <table class="table table-zebra table-xs table-pin-rows w-full border-collapse text-left text-xs">
        <thead>
          <tr class="bg-base-300">
            {#each headers as header}
              <th class="px-3 py-1.5 border border-base-300 font-bold bg-base-200">{header}</th>
            {/each}
          </tr>
        </thead>
        <tbody>
          {#each rows as row}
            <tr class="border-t border-base-content/10">
              {#each headers as _, i}
                <td class="px-3 py-1.5 border border-base-300 whitespace-nowrap text-base-content/85">
                  {row[i] ?? ""}
                </td>
              {/each}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {:else}
    <div class="p-3 text-xs text-base-content/45">Empty CSV</div>
  {/if}
</BlockFrame>
