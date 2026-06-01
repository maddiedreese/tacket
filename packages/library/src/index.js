import { createHash } from "node:crypto";
import { access, mkdir, readdir, readFile, stat } from "node:fs/promises";
import { constants } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { readBundle, readTranscript } from "@tacket/thread-format";

export function defaultLibraryDatabasePath() {
  return path.join(os.homedir(), "Library/Application Support/Tacket/library.sqlite");
}

export async function indexLibraryFolder(folder, options = {}) {
  const dbPath = expandHome(options.db ?? defaultLibraryDatabasePath());
  const root = expandHome(folder);
  await ensureSQLite();
  await initLibrary(dbPath);
  const bundles = await findTacketBundles(root);
  const indexed = [];
  const skipped = [];

  for (const bundlePath of bundles) {
    const result = await indexBundle(dbPath, bundlePath);
    if (result.indexed) indexed.push(result);
    else skipped.push(result);
  }

  return {
    dbPath,
    folder: root,
    found: bundles.length,
    indexed: indexed.length,
    skipped: skipped.length
  };
}

export async function listLibrary(options = {}) {
  const dbPath = expandHome(options.db ?? defaultLibraryDatabasePath());
  await initLibrary(dbPath);
  return queryJson(dbPath, `
    SELECT id, path, title, platform, url, captured_at AS capturedAt,
           message_count AS messageCount, indexed_at AS indexedAt
    FROM bundles
    ORDER BY captured_at DESC, indexed_at DESC;
  `);
}

export async function searchLibrary(query, options = {}) {
  const dbPath = expandHome(options.db ?? defaultLibraryDatabasePath());
  await initLibrary(dbPath);
  const trimmed = String(query ?? "").trim();
  if (!trimmed) return listLibrary(options);
  const limit = Number(options.limit ?? 50);
  if (!(await supportsFts5())) {
    return queryJson(dbPath, `
      SELECT b.id, b.path, b.title, b.platform, b.url,
             b.captured_at AS capturedAt, b.message_count AS messageCount,
             substr(m.text, 1, 240) AS snippet
      FROM messages_fts m
      JOIN bundles b ON b.id = m.bundle_id
      WHERE lower(m.text || ' ' || m.title || ' ' || m.platform || ' ' || m.role)
        LIKE ${sqlString(`%${trimmed.toLowerCase()}%`)}
        AND m.rowid IN (
          SELECT min(rowid)
          FROM messages_fts
          WHERE lower(text || ' ' || title || ' ' || platform || ' ' || role)
            LIKE ${sqlString(`%${trimmed.toLowerCase()}%`)}
          GROUP BY bundle_id
        )
      ORDER BY b.captured_at DESC, b.indexed_at DESC
      LIMIT ${limit};
    `);
  }

  const ftsQuery = ftsPhrase(trimmed);
  return queryJson(dbPath, `
    SELECT b.id, b.path, b.title, b.platform, b.url,
           b.captured_at AS capturedAt, b.message_count AS messageCount,
           snippet(messages_fts, 5, '[', ']', ' ... ', 18) AS snippet
    FROM messages_fts
    JOIN bundles b ON b.id = messages_fts.bundle_id
    WHERE messages_fts MATCH ${sqlString(ftsQuery)}
      AND messages_fts.rowid IN (
        SELECT min(rowid)
        FROM messages_fts
        WHERE messages_fts MATCH ${sqlString(ftsQuery)}
        GROUP BY bundle_id
      )
    ORDER BY rank
    LIMIT ${limit};
  `);
}

export async function removeMissingBundles(options = {}) {
  const dbPath = expandHome(options.db ?? defaultLibraryDatabasePath());
  await initLibrary(dbPath);
  const bundles = await listLibrary({ db: dbPath });
  let removed = 0;
  for (const bundle of bundles) {
    try {
      await access(bundle.path, constants.R_OK);
    } catch {
      await execSql(dbPath, `
        DELETE FROM messages_fts WHERE bundle_id = ${sqlString(bundle.id)};
        DELETE FROM messages WHERE bundle_id = ${sqlString(bundle.id)};
        DELETE FROM bundles WHERE id = ${sqlString(bundle.id)};
      `);
      removed += 1;
    }
  }
  return { dbPath, checked: bundles.length, removed };
}

export async function initLibrary(dbPath = defaultLibraryDatabasePath()) {
  await ensureSQLite();
  await mkdir(path.dirname(dbPath), { recursive: true });
  const fts5 = await supportsFts5();
  await execSql(dbPath, `
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS bundles (
      id TEXT PRIMARY KEY,
      path TEXT NOT NULL UNIQUE,
      title TEXT,
      platform TEXT,
      url TEXT,
      captured_at TEXT,
      message_count INTEGER,
      indexed_at TEXT,
      transcript_hash TEXT
    );
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      bundle_id TEXT NOT NULL,
      role TEXT,
      text TEXT,
      ordinal INTEGER,
      FOREIGN KEY(bundle_id) REFERENCES bundles(id) ON DELETE CASCADE
    );
  `);
  if (fts5) {
    await execSql(dbPath, `
    CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
      bundle_id UNINDEXED,
      message_id UNINDEXED,
      title,
      platform,
      role,
      text
    );
  `);
  } else {
    await execSql(dbPath, `
      CREATE TABLE IF NOT EXISTS messages_fts (
        bundle_id TEXT,
        message_id TEXT,
        title TEXT,
        platform TEXT,
        role TEXT,
        text TEXT
      );
      CREATE INDEX IF NOT EXISTS messages_fts_bundle_id ON messages_fts(bundle_id);
    `);
  }
}

async function indexBundle(dbPath, bundlePath) {
  const bundle = await readBundle(bundlePath);
  const transcript = await readTranscript(bundlePath);
  const transcriptHash = sha256(transcript);
  const existing = await queryJson(dbPath, `
    SELECT transcript_hash AS transcriptHash
    FROM bundles
    WHERE path = ${sqlString(bundlePath)}
    LIMIT 1;
  `);
  if (existing[0]?.transcriptHash === transcriptHash) {
    return { path: bundlePath, id: bundle.id, indexed: false };
  }

  const now = new Date().toISOString();
  const messageRows = bundle.messages.map((message, index) => ({
    id: `${bundle.id}:${message.id}`,
    role: message.role ?? "unknown",
    text: messageText(message),
    ordinal: index
  }));
  const sql = [];
  sql.push("BEGIN;");
  sql.push(`DELETE FROM messages_fts WHERE bundle_id = ${sqlString(bundle.id)};`);
  sql.push(`DELETE FROM messages WHERE bundle_id = ${sqlString(bundle.id)};`);
  sql.push(`DELETE FROM bundles WHERE path = ${sqlString(bundlePath)} OR id = ${sqlString(bundle.id)};`);
  sql.push(`
    INSERT INTO bundles (id, path, title, platform, url, captured_at, message_count, indexed_at, transcript_hash)
    VALUES (
      ${sqlString(bundle.id)},
      ${sqlString(bundlePath)},
      ${sqlString(bundle.title ?? path.basename(bundlePath))},
      ${sqlString(bundle.source?.platform ?? "unknown")},
      ${sqlString(bundle.source?.url ?? "")},
      ${sqlString(bundle.capturedAt ?? "")},
      ${Number(bundle.messageCount ?? bundle.messages.length)},
      ${sqlString(now)},
      ${sqlString(transcriptHash)}
    );
  `);
  for (const message of messageRows) {
    sql.push(`
      INSERT INTO messages (id, bundle_id, role, text, ordinal)
      VALUES (${sqlString(message.id)}, ${sqlString(bundle.id)}, ${sqlString(message.role)}, ${sqlString(message.text)}, ${message.ordinal});
      INSERT INTO messages_fts (bundle_id, message_id, title, platform, role, text)
      VALUES (
        ${sqlString(bundle.id)},
        ${sqlString(message.id)},
        ${sqlString(bundle.title ?? path.basename(bundlePath))},
        ${sqlString(bundle.source?.platform ?? "unknown")},
        ${sqlString(message.role)},
        ${sqlString(message.text)}
      );
    `);
  }
  sql.push("COMMIT;");
  await execSql(dbPath, sql.join("\n"));
  return { path: bundlePath, id: bundle.id, indexed: true };
}

async function findTacketBundles(root) {
  const found = [];
  await walk(root);
  return found.sort();

  async function walk(current) {
    const info = await stat(current);
    if (!info.isDirectory()) return;
    if (current.endsWith(".tacket")) {
      try {
        await Promise.all([
          access(path.join(current, "manifest.json"), constants.R_OK),
          access(path.join(current, "messages.jsonl"), constants.R_OK),
          access(path.join(current, "transcript.md"), constants.R_OK)
        ]);
        found.push(current);
      } catch {
        // Ignore directories that merely happen to end in .tacket.
      }
      return;
    }
    const entries = await readdir(current, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory()) await walk(path.join(current, entry.name));
    }
  }
}

function messageText(message) {
  return (message.content ?? [])
    .filter((part) => part.type === "text" || part.type === "code")
    .map((part) => part.text ?? "")
    .join("\n")
    .trim();
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function ftsPhrase(value) {
  return `"${value.replace(/"/gu, '""')}"`;
}

function sqlString(value) {
  if (value === null || value === undefined) return "NULL";
  return `'${String(value).replace(/'/gu, "''")}'`;
}

function expandHome(value) {
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return path.resolve(value);
}

async function ensureSQLite() {
  await new Promise((resolve, reject) => {
    const child = spawn("sqlite3", ["-version"], { stdio: ["ignore", "ignore", "pipe"] });
    const stderr = [];
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`sqlite3 is required for Tacket Library. ${Buffer.concat(stderr).toString("utf8")}`));
    });
  });
}

let fts5Support;

async function supportsFts5() {
  if (process.env.TACKET_DISABLE_FTS5_FOR_TESTS === "1") return false;
  if (fts5Support !== undefined) return fts5Support;
  try {
    await execSql(":memory:", "CREATE VIRTUAL TABLE t USING fts5(x);");
    fts5Support = true;
  } catch {
    fts5Support = false;
  }
  return fts5Support;
}

function execSql(dbPath, sql) {
  return new Promise((resolve, reject) => {
    const child = spawn("sqlite3", [dbPath], { stdio: ["pipe", "pipe", "pipe"] });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("exit", (code) => {
      const err = Buffer.concat(stderr).toString("utf8");
      if (code === 0) resolve(Buffer.concat(stdout).toString("utf8"));
      else reject(new Error(err || `sqlite3 exited with ${code}`));
    });
    child.stdin.end(sql);
  });
}

function queryJson(dbPath, sql) {
  return new Promise((resolve, reject) => {
    const child = spawn("sqlite3", ["-json", dbPath, sql], { stdio: ["ignore", "pipe", "pipe"] });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("exit", (code) => {
      const out = Buffer.concat(stdout).toString("utf8").trim();
      const err = Buffer.concat(stderr).toString("utf8");
      if (code !== 0) {
        reject(new Error(err || `sqlite3 exited with ${code}`));
        return;
      }
      resolve(out ? JSON.parse(out) : []);
    });
  });
}
