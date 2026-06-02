# Website

Tacket's public website is the static `website/` directory. It is deployed by Netlify from GitHub.

GitHub Pages is not used for the public website. Keep GitHub Pages disabled so `https://tacket.dev` remains the canonical site.

## Netlify Setup

1. In Netlify, choose **Add new site** and import the GitHub repository.
2. Use `main` as the production branch.
3. Set the build command to `npm run website:verify`.
4. Set the publish directory to `website`.
5. Deploy.

No environment variables or backend services are required for the website. Netlify deploy previews can be left on for pull requests.

## Local Editing

Run the website verifier before committing changes:

```bash
npm run website:verify
```

To preview locally:

```bash
python3 -m http.server 4173 --directory website
```

Then open `http://localhost:4173`.

## Separate Codex Chat

For website-only work, open a new Codex chat in this same project and start with:

```text
Work only on the Tacket website. Read website/ and docs/WEBSITE.md first. Keep app, release, and extension code unchanged unless I explicitly ask. Run npm run website:verify before finishing, and use the browser to inspect visual changes.
```

Use a separate branch such as `codex/website-polish` when the work should become a pull request.
