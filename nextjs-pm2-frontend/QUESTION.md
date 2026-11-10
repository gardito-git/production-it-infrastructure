# Questions for the Frontend team

Hi Frontend team 👋 The infrastructure for the Next.js app is ready (see [README.md](README.md)).
Before we finish the **caching** setup, we need some answers from you: the right setup depends
on how the app is built, and that's your call, not ours.

Please write your answers under each question (or reply in the ticket), even if the answer is
"we don't know yet". **None of these block the first deploy.**

## How the app runs in production

```
browser ─HTTPS─► CloudFront ─┬─ /_next/static/*  ─► S3 (cached 1 year)
                             ├─ /_next/image*    ─► Nginx ─► Next.js (cached at CloudFront)
                             └─ everything else  ─► Nginx ─► Next.js (NOT cached)
```

- **3 servers × 3 Next.js processes (PM2 cluster mode) = 9 processes**, each up to 4 GiB.
- **Each process has its own Next.js cache by default** (memory + the server's disk). So with
  ISR, `revalidate`, cached `fetch` or `"use cache"`:
  - visitors can see different versions of a page, depending on which process answers;
  - `revalidatePath()` / `revalidateTag()` only clears **one** of the 9 caches;
  - each process rebuilds the same page on its own (up to 9× the load on your APIs).
- What we can offer: a **shared Redis cache** for all 9 processes, **CloudFront caching** for
  public pages, and longer **image caching**. Your answers decide which ones are worth it.

---

## 1. Version

**1.1** Which Next.js version, and App Router, Pages Router, or both?
(Custom cache handlers work differently between versions.)

> Answer:

## 2. Which caching features does the app use?

**2.1** Tick what you use, with an example file or route if you can:

- [ ] ISR / `export const revalidate = …` / `getStaticProps` with `revalidate`
- [ ] `fetch(..., { next: { revalidate, tags } })` or `cache: "force-cache"`
- [ ] `"use cache"` / `cacheLife` / `cacheTag`
- [ ] `unstable_cache`
- [ ] On-demand revalidation: `revalidatePath()` / `revalidateTag()`
- [ ] Draft mode / preview
- [ ] None: every page is rendered on every request

> Answer:

**2.2** If you use on-demand revalidation: **what triggers it?** (A CMS webhook, an admin
action, a cron job...?) And must the change be visible **everywhere at once**?

> Answer:

**If you ticked anything other than "None", we'll set up the shared Redis cache.** You would
then add a cache handler to `next.config` (we'll provide the Redis connection details).

## 3. Which pages are the same for everyone?

**3.1** List the routes that show **exactly the same content to every visitor** (e.g. `/`,
`/about`, `/blog/*`, `/products/*`). These can be cached at CloudFront, so most of their
traffic never reaches our servers.

> Answer:

**3.2** List the routes that are **per user** (logged-in, cart, dashboard...). These are never
cached at CloudFront. Which **cookies** mark a logged-in user?

> Answer:

**3.3** Does any "public" page change by **language, country, device or A/B test**? Based on
what (a cookie, a header, the URL)?

> Answer:

**3.4** How **stale** may a public page be? (Seconds, 1 minute, 10 minutes?) After a content
change, CloudFront keeps its copy until this time runs out unless we clear it.

> Answer:

## 4. Images (`next/image`)

**4.1** Where do images come from: `public/`, your own CDN or S3, a CMS, third-party sites?
(List the `images.remotePatterns` domains.)

> Answer:

**4.2** Can an image **change while keeping the same URL**? If not, please set
`images.minimumCacheTTL` (e.g. `86400`, one day) in `next.config` so CloudFront keeps resized
images longer.

> Answer:

## 5. Size, for the Redis cache

**5.1** Roughly how many cached pages or data entries? (e.g. "5,000 product pages")

> Answer:

**5.2** Roughly how large is one cached page or `fetch` response? (KB)

> Answer:

## 6. Things to confirm for the first deploy (not caching)

- [ ] `output: "standalone"` is set in `next.config`.
- [ ] A cheap health route exists, e.g. `/api/health` returning `ok`, so the deploy script can
      check a server quickly. Path: ________
- [ ] Builds use **Node.js 24** on **Linux x86_64** (WSL or a Linux machine; not Windows),
      because native modules like `sharp` are built for the build machine.
- [ ] `NEXT_PUBLIC_*` variables needed **at build time**: ________
- [ ] Server-side variables needed **at runtime** (we put them in `/etc/frontend/app.env`; send
      secrets privately, never in this file): ________
- [ ] **Server actions during a rolling deploy:** for a minute, servers run the old and the new
      version side by side. Please set `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` to the same value
      for every build, so a form loaded from one version still works on the other.
- [ ] Does the app need anything else on the server: cron jobs, WebSockets, file uploads larger
      than 10 MB, writing files to disk?

> Answer:

---

Questions back to us? Ask the Infrastructure team. Thanks! 🙏
