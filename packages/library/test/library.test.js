import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { indexLibraryFolder, listLibrary, removeMissingBundles, searchLibrary } from "@tacket/library";
import { writeBundle } from "@tacket/thread-format";

test("indexes .tacket bundles into a local SQLite FTS library and searches raw messages", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-library-"));
  try {
    const db = path.join(root, "library.sqlite");
    await writeBundle({
      title: "Stripe webhook debugging",
      source: { url: "https://chatgpt.com/c/stripe" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "Help me debug a Stripe webhook signature failure." }]
        },
        {
          role: "assistant",
          content: [{ type: "text", text: "Preserve the raw request body before verification." }]
        }
      ]
    }, root);

    const indexed = await indexLibraryFolder(root, { db });
    assert.equal(indexed.found, 1);
    assert.equal(indexed.indexed, 1);

    const listed = await listLibrary({ db });
    assert.equal(listed.length, 1);
    assert.equal(listed[0].title, "Stripe webhook debugging");
    assert.equal(listed[0].platform, "chatgpt");

    const results = await searchLibrary("webhook", { db });
    assert.equal(results.length, 1);
    assert.equal(results[0].title, "Stripe webhook debugging");
    assert.match(results[0].snippet, /webhook/u);

    const second = await indexLibraryFolder(root, { db });
    assert.equal(second.skipped, 1);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("removeMissingBundles drops bundles that are no longer on disk", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-library-missing-"));
  try {
    const db = path.join(root, "library.sqlite");
    const { bundlePath } = await writeBundle({
      title: "Missing bundle",
      source: { url: "https://claude.ai/chat/missing" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "This bundle will be removed." }]
        }
      ]
    }, root);
    await indexLibraryFolder(root, { db });
    await rm(bundlePath, { recursive: true, force: true });

    const result = await removeMissingBundles({ db });
    assert.equal(result.checked, 1);
    assert.equal(result.removed, 1);
    assert.deepEqual(await listLibrary({ db }), []);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("indexer ignores invalid .tacket-shaped folders", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-library-invalid-"));
  try {
    const db = path.join(root, "library.sqlite");
    await writeFile(path.join(root, "not-real.tacket"), "not a directory");
    const result = await indexLibraryFolder(root, { db });
    assert.equal(result.found, 0);
    assert.deepEqual(await listLibrary({ db }), []);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
