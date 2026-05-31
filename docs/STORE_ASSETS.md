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
- Screenshots: one to five images, 1280 by 800 pixels or 640 by 400 pixels, PNG or JPEG.

Regenerate icons and the small promotional image with:

```bash
npm run generate:icons
```

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
- [ ] Small promotional image is exactly 440 by 280 pixels.
- [ ] Extension icon matches the packaged 128 pixel icon.
- [ ] The first screenshot makes Tacket's local-first raw transfer purpose obvious.
- [ ] The native messaging/local app relationship is visible in at least one screenshot.
- [ ] No screenshots imply background capture, cloud sync, analytics, or summarization.
