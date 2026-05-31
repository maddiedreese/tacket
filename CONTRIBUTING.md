# Contributing

Thanks for helping make Tacket better.

## Development

```bash
npm install
npm run verify
```

The project intentionally keeps capture and transfer local-first. Contributions should preserve these rules:

- no backend requirement
- no analytics
- no background capture
- no summarization in v1 transfer paths
- capture only after user action
- raw transcripts remain inspectable local files

## Pull Requests

Before opening a pull request:

- run `npm run verify`
- run `npm run package:release` for release-affecting changes
- update docs when user-facing behavior changes

Capture adapters should include fixture coverage in `apps/chrome-extension/test`.

## Security

Do not include private chat transcripts, tokens, screenshots, or exploit details in public issues. See `SECURITY.md` for vulnerability reporting guidance.
