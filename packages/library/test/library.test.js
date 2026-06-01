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

test("advanced search supports all-term matching and field filters", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-library-advanced-"));
  try {
    const db = path.join(root, "library.sqlite");
    await writeBundle({
      title: "Webhook retry plan",
      source: { url: "https://chatgpt.com/c/retry" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "The webhook keeps failing during signature verification." }]
        },
        {
          role: "assistant",
          content: [{ type: "text", text: "Add a retry queue after verification succeeds." }]
        }
      ]
    }, root);
    await writeBundle({
      title: "Design notes",
      source: { url: "https://claude.ai/chat/design" },
      messages: [
        {
          role: "assistant",
          content: [{ type: "text", text: "Use calm colors and compact spacing." }]
        }
      ]
    }, root);
    await indexLibraryFolder(root, { db });

    assert.equal((await searchLibrary("webhook verification", { db })).length, 0);
    const allTerms = await searchLibrary("webhook verification", { db, match: "all", scope: "transcript" });
    assert.equal(allTerms.length, 1);
    assert.equal(allTerms[0].title, "Webhook retry plan");

    const titleOnly = await searchLibrary("retry", { db, scope: "title" });
    assert.equal(titleOnly.length, 1);
    assert.equal(titleOnly[0].title, "Webhook retry plan");

    const claudeOnly = await searchLibrary("", { db, source: "claude", role: "assistant" });
    assert.equal(claudeOnly.length, 1);
    assert.equal(claudeOnly[0].title, "Design notes");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("advanced search supports any-term matching", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-library-any-"));
  try {
    const db = path.join(root, "library.sqlite");
    await writeBundle({
      title: "Database migration",
      source: { url: "https://gemini.google.com/app/migration" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "Plan the migration indexes." }]
        }
      ]
    }, root);
    await indexLibraryFolder(root, { db });

    const results = await searchLibrary("missing migration", { db, match: "any", scope: "transcript" });
    assert.equal(results.length, 1);
    assert.equal(results[0].title, "Database migration");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("falls back to local LIKE search when SQLite FTS5 is unavailable", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-library-like-"));
  const previous = process.env.TACKET_DISABLE_FTS5_FOR_TESTS;
  process.env.TACKET_DISABLE_FTS5_FOR_TESTS = "1";
  try {
    const db = path.join(root, "library.sqlite");
    await writeBundle({
      title: "Fallback search",
      source: { url: "https://gemini.google.com/app/fallback" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "Find the local-only repository search fallback." }]
        }
      ]
    }, root);
    await indexLibraryFolder(root, { db });
    const results = await searchLibrary("repository search", { db });
    assert.equal(results.length, 1);
    assert.equal(results[0].title, "Fallback search");
  } finally {
    if (previous === undefined) delete process.env.TACKET_DISABLE_FTS5_FOR_TESTS;
    else process.env.TACKET_DISABLE_FTS5_FOR_TESTS = previous;
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
