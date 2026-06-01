# `.tacket` Bundle Format

A `.tacket` folder is a directory containing one saved AI chat conversation and supporting files.

```text
2026-06-01 10.51 - ChatGPT - Planning the app.tacket/
  README.md
  manifest.json
  messages.jsonl
  transcript.md
  attachments/
  targets/
```

Folder names are meant for Finder first: save date and time, source platform, then chat title. When a name already exists, Tacket appends a Finder-style suffix such as `(2)`.

`README.md` is a short human-readable guide to the bundle. The source of truth remains `manifest.json`, `messages.jsonl`, and `transcript.md`.

## `manifest.json`

The manifest records save metadata, source platform, counts, and attachment status.

It may also include local-only warnings:

```json
{
  "warnings": [
    {
      "type": "possible_secret",
      "kind": "openai_api_key",
      "count": 1,
      "messageIds": ["chatgpt-1"]
    }
  ]
}
```

Warnings are advisory metadata. They do not redact or modify `messages.jsonl` or `transcript.md`.

## `messages.jsonl`

Each line is one message object. The JSONL format keeps large threads stream-friendly and easy to inspect.

The public schema files live in `schemas/manifest.schema.json` and `schemas/message.schema.json`. Validate a bundle with:

```bash
node scripts/validate-bundle.mjs path/to/thread.tacket
```

## `transcript.md`

The transcript is a readable rendering for paste transfer. It includes a small transfer envelope, then each saved message in order. It is not a summary and does not replace `messages.jsonl`.

Long conversations may be transferred as ordered chunks:

```text
[conversation chunk 1 of 3]

...

Please acknowledge receipt only.
```

The final chunk ends with:

```text
[conversation complete]
```

## Attachments

Attachments can have one of three statuses:

- `captured`: Tacket saved a local copy.
- `referenced`: Tacket preserved a URL or page reference but could not save the bytes.
- `unavailable`: Tacket saw an attachment placeholder but could not access it.

`node scripts/validate-bundle.mjs path/to/thread.tacket` verifies schema shape, message counts, attachment counts, captured attachment files, safe relative attachment paths, and that `targets/codex.md` and `targets/claude-code.md` match `transcript.md` exactly.
