# App Store Submission Kit — MirrorKit 1.0.0

Everything you need to fill out App Store Connect for the MirrorKit launch.
Each file is numbered in the order you'll need it.

## Files

| # | File | Where it goes in App Store Connect |
|---|------|-----------------------------------|
| 01 | `01-app-name-subtitle.md` | App Information → Name + Subtitle |
| 02 | `02-promotional-text.md` | Version → Promotional Text |
| 03 | `03-description.md` | Version → Description |
| 04 | `04-keywords.md` | Version → Keywords |
| 05 | `05-whats-new.md` | Version → What's New in This Version |
| 06 | `06-categories-pricing.md` | App Information → Category + Pricing and Availability |
| 07 | `07-app-privacy.md` | App Privacy section |
| 08 | `08-review-notes.md` | App Review Information → Notes + Contact |
| 09 | `09-privacy-policy.html` | Host on GitHub Pages, then paste URL |
| 10 | `10-support-page.html` | Host on GitHub Pages, then paste URL |

## Hosting the HTML pages on GitHub Pages

1. Create a new public GitHub repo, e.g. `mirrorkit-site`.
2. Copy `09-privacy-policy.html` as `privacy.html` and `10-support-page.html` as `index.html` (or `support.html`) into the repo.
3. Repo Settings → Pages → Source: `main` branch, root.
4. Wait ~1 min, your URLs will be:
   - `https://<your-github-username>.github.io/mirrorkit-site/privacy.html`
   - `https://<your-github-username>.github.io/mirrorkit-site/`
5. Paste those URLs into App Store Connect:
   - Privacy Policy URL → privacy.html URL
   - Support URL → index URL
   - Marketing URL → index URL (optional)

## Screenshots
The 6 screenshots are ready in `../Screenshots/final/`. Upload all six in the **macOS App Previews and Screenshots** section.

## Final submission checklist

- [ ] Build 1.0.0 (2) is processed and visible in App Store Connect
- [ ] All metadata fields filled (files 01–06)
- [ ] App Privacy questionnaire completed (file 07): Data Not Collected
- [ ] Privacy Policy URL set
- [ ] Support URL set
- [ ] 6 screenshots uploaded (2880×1800)
- [ ] App Review Information notes added (file 08)
- [ ] Pricing tier 10 set
- [ ] Availability set to all countries
- [ ] Export Compliance: No encryption (or "Yes, exempt" if HTTPS later)
- [ ] Click **Add for Review** → **Submit to App Review**
