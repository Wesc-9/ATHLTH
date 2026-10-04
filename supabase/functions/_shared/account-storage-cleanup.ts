type StorageObject = { bucket_id: string; name: string };

// Enumerate ownership across every bucket, including files outside user folders.
// Re-read the first page after removing it: offsets would skip remaining objects.
export async function removeAccountStorage(
  userID: string,
  list: (userID: string, limit: number) => Promise<StorageObject[]>,
  remove: (bucket: string, paths: string[]) => Promise<void>,
): Promise<void> {
  const deadline = Date.now() + 90_000;
  let previousPage: string | undefined;
  while (true) {
    if (Date.now() >= deadline) throw new Error("Storage cleanup timed out; retry deletion.");
    const objects = await list(userID, 100);
    if (objects.length === 0) return;
    const page = JSON.stringify(objects);
    if (page === previousPage) throw new Error("Storage cleanup made no progress.");
    previousPage = page;
    const buckets = new Map<string, string[]>();
    for (const object of objects) {
      const paths = buckets.get(object.bucket_id) ?? [];
      paths.push(object.name);
      buckets.set(object.bucket_id, paths);
    }
    for (const [bucket, paths] of buckets) await remove(bucket, paths);
  }
}
