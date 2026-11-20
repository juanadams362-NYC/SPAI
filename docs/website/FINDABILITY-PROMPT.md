# Prompt 2: make spai-vision findable and buyable

Run this **after** `UPDATE-PROMPT.md` has been done. It comes from the marketing audit of Nov 13, 2026. I checked the audit's main findings against the live site on Nov 20, 2026, and they still hold: `/robots.txt`, `/sitemap.xml`, `/privacy`, `/terms` and any made-up path all return the homepage with status 200; the homepage opens on the "Begin cycle" loader; the only contact is a personal Gmail; the site has no JSON-LD and no `twitter:title`.

Fill in the `[YOU FILL IN]` items first. If you haven't bought the domain or set up the inbox yet, run it anyway: the session leaves those parts as clearly marked TODOs.

---

Make spai-vision findable by search engines and credible to a school or hospital buyer. Keep the design system, every video and the voice from the last update. Invent nothing: no customers, logos, testimonials, prices, ratings, addresses or phone numbers.

## 1. Homepage: say what SPAI is before anything else

- The first screen is now a plain, static offer rendered in the HTML (not by JavaScript or WebGL):
  - H1: **Sterile processing, seen through AI.**
  - One sentence: **SPAI is a training assistant for Apple Vision Pro that guides sterile processing students through each station, checks gloves and names instruments on the headset, and gives instructors a scored record of every run.**
  - Primary button: **Book a demo** (to `/demo`). Secondary: **Try it live** (to `/try`). Text link: **Watch the experience**, which starts the existing cinematic cycle.
- The "Begin cycle" loader and scroll-driven WebGL experience stay, but only as that opt-in. Nobody has to go through them to reach the offer.
- Don't preload `/media/hero.mp4` or the WebGL bundle until the visitor starts the experience.
- Add a **Book a demo** button to the header on every page, home included.

## 2. Files and settings search engines need

- `robots.txt`: allow everything, and point to the sitemap.
- `sitemap.xml`: the content pages only: `/`, `/how-it-works`, `/try`, `/schools`, `/hospitals`, `/plans`, `/about`, `/faq`, `/demo`, `/privacy`, `/terms`.
- **Real 404s.** Unknown paths must return HTTP 404 with a small "page not found" page that links home and to Book a demo. On Cloudflare Pages, a top-level `404.html` does this; check that the build doesn't fall back to the homepage.
- Every page: fill in `twitter:title`, `twitter:description` (same as the OG ones), and keep the unique title, description, canonical and OG image each page already has.
- JSON-LD:
  - `Organization` on every page: name, URL, logo, `sameAs` with the GitHub repo. No address or phone.
  - `SoftwareApplication` on `/` and `/how-it-works`: name, `operatingSystem: visionOS`, `applicationCategory: EducationalApplication`, the one-sentence description. No price, no rating.
  - `FAQPage` on `/faq`, built from the questions and answers actually on the page.
- Add a placeholder for the Google Search Console verification tag: `[YOU FILL IN — the meta tag Search Console gives you, or leave a TODO comment]`.
- Canonicals and `og:url` use one site address, set in one place so the domain can change with a single edit: `[YOU FILL IN — https://your-new-domain, or keep https://spai-vision.pages.dev for now]`.

## 3. A contact path that looks like a company

- Contact address: `[YOU FILL IN — e.g. hello@your-new-domain, or "keep Gmail for now"]`. Use it in every footer and on the demo page. If I said "keep Gmail for now", leave the Gmail and add a TODO comment at each place it appears, so they're easy to find later.
- The demo form keeps all its fields and the honeypot. Send it to the new address. If I've kept the Gmail for now, leave formsubmit as it is.
- On `/demo`, say what happens next: a reply within two business days and a one-hour walkthrough (the current promise). Don't add a calendar link unless I give you one: `[YOU FILL IN — booking link, or delete]`.

## 4. Pages buyers look for

- **`/privacy`**: a real page built from the "Privacy and data" facts used in the last update (frames stay on the headset by default, what is stored, what is never collected, deletion and export, the Gemini disclosure for Ask SPAI, each school's records kept separate). Add the date and the contact address.
- **`/terms`**: short and honest: SPAI is a pilot-stage training and workflow-guidance tool, not a medical device; the pilot terms are agreed in writing with each school. Mark the page "Draft, pending legal review" in an HTML comment, not on the page.
- Link both from every footer.

## 5. One name, one set of numbers

- The product is **SPAI**, and the full name is **SPAI Vision**: use "SPAI Vision" in titles, the Organization schema and the first mention on each page, because bare "SPAI" is a crowded search term. Don't use "Surgical Prep AI" anywhere.
- Every cited statistic links to its source. If the source URL isn't already in the code or copy, leave the statistic as it is with a TODO comment. Don't guess a URL.
- Check that every page says the glove model is "v3 · 94.8" and the instrument model is v5 (from the last update).

## 6. Measurement

- Keep the Cloudflare Web Analytics beacon. Don't add Google Analytics, Tag Manager or any ad pixel: they set cookies, which would need a consent banner, and school IT offices notice that.
- To count demo requests, have the form handler log each submission (date, request type, institution type), not a tracking tag.

## When you're done

List every file you changed. Then give me the commands to check the result, for example `curl -sI <site>/robots.txt` (should be `text/plain`) and `curl -sI <site>/no-such-page` (should be `404`), and list every `[YOU FILL IN]` and TODO still open.
