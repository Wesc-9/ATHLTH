import test from "node:test";
import assert from "node:assert/strict";
import { removeAccountStorage } from "./account-storage-cleanup.ts";

test("deletion drains multiple pages and buckets without skipping files", async () => {
  let objects = Array.from({ length: 235 }, (_, i) => ({
    bucket_id: i % 2 ? "workout-media" : "community-content-images", name: `group/${i}.jpg`,
  }));
  const removed: string[] = [];
  await removeAccountStorage("owner", async (userID, limit) => {
    assert.equal(userID, "owner");
    return objects.slice(0, limit);
  }, async (bucket, paths) => {
    assert.ok(paths.length <= 100);
    removed.push(...paths);
    objects = objects.filter(o => o.bucket_id !== bucket || !paths.includes(o.name));
  });
  assert.equal(objects.length, 0);
  assert.equal(new Set(removed).size, 235);
});

test("partial failure propagates and a retry removes the remaining files", async () => {
  let objects = [{ bucket_id: "avatars", name: "a" }, { bucket_id: "gear", name: "b" }];
  const list = async () => objects;
  await assert.rejects(removeAccountStorage("owner", list, async bucket => {
    if (bucket === "gear") throw new Error("Storage unavailable");
    objects = objects.filter(o => o.bucket_id !== bucket);
  }), /Storage unavailable/);
  assert.deepEqual(objects, [{ bucket_id: "gear", name: "b" }]);
  await removeAccountStorage("owner", list, async bucket => {
    objects = objects.filter(o => o.bucket_id !== bucket);
  });
  assert.equal(objects.length, 0);
});

test("failed inventory and non-progressing deletes stop cleanup", async () => {
  await assert.rejects(removeAccountStorage("owner", async () => { throw new Error("RPC failed"); }, async () => {}), /RPC failed/);
  await assert.rejects(removeAccountStorage("owner", async () => [{ bucket_id: "gear", name: "b" }], async () => {}), /no progress/);
});
