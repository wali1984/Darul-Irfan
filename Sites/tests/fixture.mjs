import { build } from "../../Server/node_modules/esbuild/lib/main.js";
import { mkdtemp, unlink, rmdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export async function loadWorker() {
  const directory = await mkdtemp(join(tmpdir(), "darul-sites-test-"));
  const output = join(directory, "worker.mjs");
  await build({ entryPoints: [fileURLToPath(new URL("../src/index.js", import.meta.url))], outfile: output,
    bundle: true, format: "esm", platform: "neutral", target: "es2022", loader: { ".txt": "text", ".webp": "binary" } });
  const worker = (await import(pathToFileURL(output).href)).default;
  return { worker, close: async () => { await unlink(output); await rmdir(directory); } };
}

export function environment(handler) {
  return { CLOSED_DOMAINS: "naqshbandiaowaisiah.us", API: { fetch: handler ?? (async request => {
    const path = new URL(request.url).pathname;
    if (path === "/v1/public/live") return Response.json({ halqahs: [{ id: "our-sheikh", name: "Our Sheikh", live: null, stage: null }] });
    return Response.json({});
  }) } };
}
