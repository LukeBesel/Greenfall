# Greenfall website

Static site: plain HTML, CSS and a little vanilla JS. There is no build step, so it runs on GitHub Pages, Netlify, Cloudflare Pages or any static host.

```
website/
  index.html        home: hero + trailer/slideshow, story, features, before/after, gallery, buy direct, demo, newsletter, FAQ
  presskit.html     press kit: fact sheet, description, history, features, screenshots + zip, logos, contact
  privacy.html      privacy note (newsletter only, no tracking cookies)
  404.html          not-found page (uses root-relative paths, so it works best on a custom domain)
  config.js         ALL placeholders and switches. Edit this file to go live.
  css/site.css      styles (palette from ui/ui_theme.gd)
  js/main.js        slideshow, trailer, lightbox, newsletter, buy button, scroll reveal
  assets/img/       screenshots as WebP (full <= 1600 px / 250 KB, plus -640 thumbnails)
  assets/brand/     logo (SVG/PNG, light and dark), sprout mark, Lumi icon
  assets/press/     greenfall-screenshots.zip for press
  assets/fonts/     Inter and Anonymous Pro (the game's UI font), both SIL OFL, self-hosted
```

## Preview locally

```sh
cd website
python3 -m http.server 8000
# open http://localhost:8000
```

Smoke test (Playwright with Chromium): screenshots at 1440 px and 390 px, horizontal scroll, console errors, broken images, lightbox:

```sh
(cd website && python3 -m http.server 8765) &
node tools/website_check.js http://localhost:8765 screenshots/website
```

## Publish on GitHub Pages

1. Merge to `main`. `.github/workflows/pages.yml` deploys `website/` whenever something under `website/` changes on `main` (or run it by hand: Actions > Deploy website > Run workflow). It does not touch the game build (`build.yml`).
2. One time: repo **Settings > Pages > Build and deployment > Source: GitHub Actions**.
3. The site appears at `https://<user>.github.io/<repo>/`. Pages on a private repo needs a paid GitHub plan.

### Custom domain

1. Add a file `website/CNAME` containing just the domain, e.g. `greenfallgame.com`, and push.
2. At your DNS provider: for an apex domain add `A` records to `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153` (and `AAAA` `2606:50c0:8000::153` ... `8003::153` if you want IPv6); for `www` add a `CNAME` to `<user>.github.io`.
3. Settings > Pages > Custom domain: enter the domain, wait for the DNS check, then tick **Enforce HTTPS**.
4. Search and replace `https://greenfall.example` with your real address in `index.html`, `presskit.html`, `privacy.html`, `robots.txt`, `sitemap.xml` and `config.js` (`siteUrl`). The Open Graph/Twitter tags must be absolute URLs and crawlers don't run JavaScript, so they can't come from config.js.

## Going live: what to fill in (config.js)

| Key | What |
| --- | --- |
| `steam.appId` | Steam app id. Until set, "Wishlist on Steam" scrolls to the newsletter and shows a "Steam page goes live soon" note. |
| `trailer.youtubeId` or `trailer.videoUrl` | Replaces the screenshot slideshow with a play button. YouTube loads from youtube-nocookie.com only after a click. |
| `newsletter.*` | See below. |
| `buyDirect.*` | See below. |
| `demo.url` | itch.io page or Steam demo link. |
| `releaseDate`, `price`, `developer`, `basedIn` | Shown in the FAQ, footer and press kit. |
| `contactEmail` | Use a role address (press@...), not a personal one. |
| `socials.*` | Full URLs; empty ones are hidden. A Steam link is added automatically once `steam.appId` is set. |

### Newsletter

The form posts into a hidden iframe, so it works with any provider without CORS or extra scripts, then shows a thank-you message. A honeypot field silently drops bots. Set:

- **Buttondown**: `action: 'https://buttondown.com/api/emails/embed-subscribe/<username>'`, `emailField: 'email'`.
- **Mailchimp**: Audience > Signup forms > Embedded form; copy the `<form action="...">` URL (`https://<dc>.list-manage.com/subscribe/post?u=...&id=...`), `emailField: 'EMAIL'`.
- **Kit (ConvertKit)**: `action: 'https://app.kit.com/forms/<formId>/subscriptions'`, `emailField: 'email_address'`.

Turn on double opt-in at the provider. While `action` is empty the form says signups open soon.

### Buy direct

Set `buyDirect.enabled: true` and pick a provider:

- **Lemon Squeezy**: `provider: 'lemonsqueezy'`, `url:` the product's checkout link. Opens as an overlay (lemon.js).
- **Paddle** (Billing): `provider: 'paddle'`, `paddleClientToken` (client-side token, safe to publish), `paddlePriceId`. Test with `paddleEnvironment: 'sandbox'` first. Add the site domain to Paddle's approved domains.
- **itch.io**: `provider: 'itch'`, `itchGameId` (from Distribute > Embed game). Shows itch's buy widget.
- **Anything else**: `provider: 'link'`, `url`.

Valve's rule: never offer a better deal than Steam (base price, discounts, bundles). Keep `priceNote` true to that. Steam keys you sell yourself must be sold at a price comparable to Steam.

## Refreshing the screenshots

`tools/website_assets.py` rebuilds every image from the game's screenshots: WebP full size + thumbnails, hero crops without HUD, favicons from Lumi's face, the Open Graph image, the press zip, and the gallery block in `index.html` (between `<!-- gallery:start -->` and `<!-- gallery:end -->`).

```sh
python3 tools/website_assets.py --src /path/to/screenshots
```

Edit the `SHOTS` list in the script to swap images (keep the gallery at 11, 14, 17... shots so the grid has no gaps). If `<src>/steam/` exists, capsule/header art is copied to `assets/steam/` and the other store screenshots join the gallery. Needs Pillow with WebP support. The hero slideshow images are listed directly in `index.html`.

Keep `website/` under ~8 MB (it's about 5 MB now).
