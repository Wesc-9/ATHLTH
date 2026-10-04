// Admin maintenance after deploying the private-bucket migration.
// Dry-run by default. Set SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in the
// environment; never commit credentials. --apply updates bytes through Storage
// so CDN invalidation is triggered and future browser caching is limited to 60s.
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !key) throw new Error("Missing Supabase admin environment variables.");
const apply = Deno.args.includes("--apply");
const storage = createClient(url, key, {
  auth: { persistSession: false, autoRefreshToken: false },
}).storage.from("workout-media");
let count = 0;

async function visit(prefix: string): Promise<void> {
  for (let offset = 0; ; offset += 100) {
    const { data, error } = await storage.list(prefix, {
      limit: 100, offset, sortBy: { column: "name", order: "asc" },
    });
    if (error) throw error;
    for (const item of data) {
      const path = prefix ? `${prefix}/${item.name}` : item.name;
      if (!item.id) { await visit(path); continue; }
      if (apply) {
        const { data: bytes, error: downloadError } = await storage.download(path);
        if (downloadError) throw downloadError;
        const { error: updateError } = await storage.update(path, bytes, {
          cacheControl: "60", contentType: item.metadata?.mimetype ?? bytes.type,
        });
        if (updateError) throw updateError;
      }
      count += 1;
    }
    if (data.length < 100) break;
  }
}

await visit("");
console.log(`${apply ? "Refreshed" : "Would refresh"} ${count} workout-media objects.`);
