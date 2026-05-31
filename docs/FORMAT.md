# `.tacket` Bundle Format

A `.tacket` bundle is a directory containing raw thread data and renderings.

```text
capture-name.tacket/
  manifest.json
  messages.jsonl
  transcript.md
  attachments/
  targets/
```

## `manifest.json`

The manifest records capture metadata, source platform, counts, and attachment status.

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

The transcript is a raw rendering for paste transfer. It includes a small transfer envelope, then each captured message in order. It is not a summary and does not replace `messages.jsonl`.

Long transcripts may be transferred as ordered raw chunks:

```text
[raw transcript chunk 1 of 3]

...

Please acknowledge receipt only.
```

The final chunk ends with:

```text
[raw transcript complete]
```

## Attachments

Attachments can have one of three statuses:

- `captured`: Tacket saved a local copy.
- `referenced`: Tacket preserved a URL or page reference but could not save the bytes.
- `unavailable`: Tacket saw an attachment placeholder but could not access it.

`node scripts/validate-bundle.mjs path/to/thread.tacket` verifies schema shape, message counts, attachment counts, captured attachment files, safe relative attachment paths, and that `targets/codex.md` and `targets/claude-code.md` match `transcript.md` exactly.
