# Source adapters — official first-party access

Researched 22 September 2026 against owner docs / endpoints. No unofficial scrapers.

---

## 1. arXiv paper

**URL patterns**

- Abstract: `https://arxiv.org/abs/{id}` (optional `vN`)
- PDF: `https://arxiv.org/pdf/{id}`
- HTML (when conversion exists): `https://arxiv.org/html/{id}`
- Source: `https://arxiv.org/src/{id}` and `https://arxiv.org/e-print/{id}`
- Metadata API: `https://export.arxiv.org/api/query?id_list={id}`

**Chosen method**

1. `GET https://export.arxiv.org/api/query?id_list={id}` → Atom 1.0 XML metadata (title, authors, abstract, abs/pdf links). No API key.
2. Prefer full text from `GET /pdf/{id}` (`application/pdf`) and/or `GET /html/{id}` (`text/html`) when present.
3. For TeX source: `GET /src/{id}` (always a gzipped tar per docs) or `/e-print/{id}` (single gzipped file or gzipped tar). Unpack with gzip/tar.

**Auth:** none. Rate limit for legacy API: ≤1 request / 3 s, one connection ([Terms of Use](https://info.arxiv.org/help/api/tou.html)).

**You get:** metadata; PDF for essentially all posted papers; experimental HTML for many TeX papers; TeX/other source when the submitter supplied source.

**You cannot get:** HTML for papers that fail conversion or were never converted ([accessible HTML](https://info.arxiv.org/about/accessible_HTML.html)); source for PDF-only submissions — those are PDF-only ([PDF help](https://info.arxiv.org/help/pdf.html)); redistribution of e-print files unless the paper’s license allows it ([API ToU](https://info.arxiv.org/help/api/tou.html)).

**Primary docs:** [API User’s Manual](https://info.arxiv.org/help/api/user-manual.html), [API Basics](https://info.arxiv.org/help/api/basics.html), [Viewing](https://info.arxiv.org/help/view.html), [Media types](https://info.arxiv.org/help/mimetypes.html), [Unpacking](https://info.arxiv.org/help/unpack.html).

---

## 2. X / Twitter status & X Article

**URL patterns**

- Status: `https://x.com/{user}/status/{id}` (also `twitter.com`)
- Articles: long-form posts; public read URL is not specified as a separate oEmbed resource in X docs. Articles API is create/publish only.

**Chosen method (status):** official oEmbed, no bearer token.

```http
GET https://publish.x.com/oembed?url={urlencoded_status_url}
```

**Auth:** none (`Requires authentication? No`) ([oEmbed API](https://docs.x.com/x-for-websites/oembed-api)).

**You get:** oEmbed JSON (`type: rich`) with `html` = a `<blockquote class="twitter-tweet">` containing **that post’s text** (plus author metadata). Widget JS upgrades the blockquote; `hide_thread` can omit the previous post in a reply chain from the embed UI — this is still one status, not a full thread dump. Not article body.

**Optional structured text (status only):** X API v2 Post Lookup `GET https://api.x.com/2/tweets/{id}` — requires a developer App and **Bearer / OAuth** (`BearerToken` or user token with `tweet.read`) ([Post Lookup](https://docs.x.com/x-api/posts/lookup/introduction), [Get Post by ID](https://docs.x.com/x-api/posts/get-post-by-id)). Returns post fields (≤280 chars text, expansions), not Article body.

**X Articles:** documented endpoints are only `POST /2/articles/draft` and `POST /2/articles/{id}/publish` (user OAuth, write scopes). No documented public read/lookup for Article body ([Articles intro](https://docs.x.com/x-api/articles/introduction)).

**You cannot get (officially):** full thread as one document via oEmbed; Article long-form body via oEmbed or a documented read API; status media binaries as files from oEmbed alone.

---

## 3. Substack post (`*.substack.com/p/...`)

**URL patterns**

- Post: `https://{publication}.substack.com/p/{slug}` (custom domains also host posts)
- Publication RSS: `https://{publication}.substack.com/feed`

**Chosen method**

1. Resolve post URL → if free/public, `GET` the post HTML (document is the public page).
2. Or match the post’s `<link>` / GUID in `GET https://{publication}.substack.com/feed` and use `content:encoded` (RSS 2.0 with content namespace; no credential for the public feed).

**Auth:** none for public RSS and public post pages ([RSS help](https://support.substack.com/hc/en-us/articles/360038239391-Is-there-an-RSS-feed-for-my-publication)).

**Official API:** [Developer API Terms](https://substack.com/api-tos) (updated 8 Jan 2026) authorize only **public profile/publication metadata** (name, profile/publication URLs, subscriber count, badges, etc.) — **not post bodies**. No first-party documented post-content API for importers.

**Article extractor:** yes for **public/free** posts — the served HTML (and RSS `content:encoded`) is the document. Paid/subscriber-only body is not available without a subscription; public surfaces show paywalled/preview content only. Embeds exist for sites ([embed help](https://support.substack.com/hc/en-us/articles/25665267911572-How-do-I-embed-Substack-posts-or-notes-on-a-website)) but are not a full-text API.

**You cannot get:** paid full text without auth/subscription; a documented JSON post API for arbitrary URLs.

---

## 4. ChatGPT share (`chatgpt.com/share/...`)

**URL patterns**

- Conversation share: `https://chatgpt.com/share/{id}`
- Scheduled-task share (different product): `https://chatgpt.com/s/...` — out of scope for conversation import

**Chosen method:** open/fetch the **public share HTML page**. Personal-account links are viewable by anyone with the URL ([Sharing conversations…](https://help.openai.com/en/articles/7925741-sharing-conversations-and-scheduled-tasks-in-chatgpt)). No documented public JSON API for share consumers.

**Auth:** none for a personal-account public share link. Workspace shares may be restricted to that workspace.

**Documented structured fields (owner export only, not for arbitrary share URLs):** personal data export includes `shared_conversations.json` with **shared-link ID, conversation ID, title, anonymity** — not a documented message list for third-party importers of someone else’s link (same OpenAI article, Data exports section; [Exporting data](https://help.openai.com/en/articles/7260999-exporting-your-chatgpt-history-and-data)).

**On the share page itself:** OpenAI documents that a shared conversation can include conversation history, an individual assistant response, supported images, or uploaded files (snapshot at create/update). There is **no official field schema** published for title/messages JSON on the share endpoint. Do not use private ChatGPT conversation APIs.

**You cannot get:** a documented machine-readable share JSON contract; messages after the snapshot unless the owner updates the link; workspace-restricted shares from outside the workspace.

---

## Quick pick per source

| Source | Preferred official path |
| --- | --- |
| arXiv | `export.arxiv.org` Atom + `/pdf` and/or `/html`; `/src` if TeX needed |
| X status | `publish.x.com/oembed` (no token); Post Lookup if you already have API access |
| X Article | No official public read/import path documented |
| Substack | Public post HTML and/or publication `/feed` |
| ChatGPT share | Public `chatgpt.com/share/...` HTML page only |
