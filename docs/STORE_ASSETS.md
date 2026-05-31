# Store Assets

Tacket's Chrome Web Store submission should use only synthetic or demo content. Do not use private AI chat transcripts, private code, customer data, real tokens, personal file names, or screenshots from a private account.

Chrome's current image guidance says the extension icon, a small promotional image, and at least one screenshot are mandatory. Screenshots should be either 1280 by 800 pixels or 640 by 400 pixels. Use the larger 1280 by 800 size unless the UI becomes unreadable.

Source:

```text
https://developer.chrome.com/docs/webstore/images
```

## Required Assets

- Extension icon: already generated at `apps/chrome-extension/icons/tacket-128.png`.
- Small promotional image: generated at `store-assets/chrome-web-store/small-promo-440x280.png`.
- Screenshots: generated under `store-assets/chrome-web-store/screenshots/`.

Regenerate icons and the small promotional image with:

```bash
npm run generate:icons
```

Regenerate the synthetic Chrome Web Store screenshots with:

```bash
npm run store:screenshots
```

This script uses local Google Chrome in headless mode to render demo-only HTML scenes. Review the generated screenshots before submission.

Prepare the local Chrome Web Store upload folder with:

```bash
npm run store:prepare
```

This writes `dist/chrome-web-store/` with the extension zip, required 128 pixel icon, small promotional image, screenshots, `listing.md`, `privacy.md`, and a short upload README. The command regenerates icons and synthetic screenshots, verifies the packaged extension zip, then copies assets.

## Screenshot Set

Prepare screenshots from synthetic data that show:

- extension popup before capture
- successful capture result with a local bundle path
- Tacket Mac app connector setup
- Tacket Mac app selected bundle review with local warning display
- Tacket Mac app transfer target selector
- local `.tacket` bundle files in Finder

## Capture Rules

- Use a demo Chrome profile or a test account.
- Use `examples/capture-demo/index.html` or a synthetic provider thread.
- Keep local usernames out of visible file paths when possible.
- Do not show raw transcript text that came from a private conversation.
- Do not show API keys, tokens, private repository names, or private attachment names.
- Recreate screenshots after any visible UI change before submitting a new store version.

## Review Checklist

- [ ] Every image uses synthetic or non-sensitive content.
- [ ] Screenshots are exactly 1280 by 800 or 640 by 400 pixels.
- [ ] Generated screenshots have been reviewed after running `npm run store:screenshots`.
- [ ] Small promotional image is exactly 440 by 280 pixels.
- [ ] Extension icon matches the packaged 128 pixel icon.
- [ ] The first screenshot makes Tacket's local-first raw transfer purpose obvious.
- [ ] The native messaging/local app relationship is visible in at least one screenshot.
- [ ] No screenshots imply background capture, cloud sync, analytics, or summarization.
