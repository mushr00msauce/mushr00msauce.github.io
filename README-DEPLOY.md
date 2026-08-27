# Deploying the reveal splash to themushbox.com

GitHub Pages always serves whatever is at the repo root as `index.html`, so the
splash has to *become* the new `index.html`, and your current homepage moves to
its own file (`home.html`) that the splash redirects to once the video ends.

## What's in this package
- `index.html` — the new splash page (full-screen video, skip button, sound toggle)
- `assets/videos/mushbox-cage-reveal.mp4` — your uploaded reveal video
- `assets/videos/mushbox-cage-reveal-poster.jpg` — a still frame shown while the video loads
- `assets/img/mushbox-logo.png` — your real logo, background removed, ready for a dark backdrop

## Steps (in `mushr00msauce/mushr00msauce.github.io`)

1. **Rename your current homepage** so it isn't overwritten:
   ```
   git mv index.html home.html
   ```

2. **Add the splash + video** — copy these into the repo root:
   - `index.html` (from this package — replaces the one you just renamed away)
   - `assets/videos/mushbox-cage-reveal.mp4`
   - `assets/videos/mushbox-cage-reveal-poster.jpg`
   - `assets/img/mushbox-logo.png`

3. **Check internal links inside `home.html`** for anything pointing back to
   `index.html` or `/` (e.g. your logo, a "Home" nav link, `og:url`/`canonical`
   tags). Point those at `home.html` instead — otherwise clicking "home" from
   your own site bounces people back into the splash. This is the one manual
   check I can't do for you without the full page source.

4. **Commit and push:**
   ```
   git add index.html home.html assets/videos/mushbox-cage-reveal.mp4 assets/videos/mushbox-cage-reveal-poster.jpg assets/img/mushbox-logo.png
   git commit -m "Add reveal video splash before homepage"
   git push
   ```

5. **Test** at themushbox.com — the video should autoplay muted, show a Skip
   button and a Sound toggle, and land on your real homepage either when the
   clip ends (~10s) or when Skip is clicked.

## How it behaves
- Plays **every visit** (no "seen it once" memory), per your call.
- **Skip button** jumps straight to `home.html`.
- Tries to autoplay **with sound on**. Most browsers only allow that once a
  visitor has interacted with your site before (or built up enough "media
  engagement" with the domain) — first-time visitors will often still get it
  muted automatically, since browsers block unmuted autoplay outright. Either
  way the reveal still plays instead of stalling, and the **Sound** button
  lets anyone turn audio on/off themselves.
- If the video ever fails to load (slow connection, blocked autoplay, etc.),
  a 13-second safety timer sends people to `home.html` anyway — nobody gets
  stuck on a blank splash.
- The `<head>` of the splash carries the **same title/description/Open Graph
  tags** as your current homepage, so link previews on Discord/X/iMessage
  still show the real Mushbox card instead of a blank one.

## To change later
- **Redirect target:** edit `DESTINATION` near the top of the `<script>` in `index.html`.
- **Safety timeout:** edit `MAX_WAIT_MS` (currently 13000ms).
- **Swap the video:** replace `assets/videos/mushbox-cage-reveal.mp4` (keep the filename, or update the `<video src="...">` path).
