# Source identity: four questions, decided

Four rules decide how a link becomes a material and what it is called. Each had several homes. The owner decided on 2026-11-08; the options stay below as the record of what was rejected. Implemented on the `unification` branch.

## 1. Which kind a URL is

**Decided: the two sides keep their own tables.** A page is `claude`, `chatgpt` or `substack` to the server, because each is parsed differently; to the app it is one article. Unifying the tables would teach the app server-side distinctions it does not use, and sharing a host table would make one process's parsing vocabulary a dependency of the other. The boundary agrees on the wire format only — see AGENTS.md, "Across the boundary". The YouTube address fixture stays as a test of the shared contract, not as a shared table; a new host is added where it is parsed.

Rejected: the server answers the kind (an offline link has no kind); a shared host table (two loaders for a distinction the app does not need).

## 2. Who publishes the page

**Decided: the server is canonical, the app falls back.** The server already writes `material.source` into the delivery. The app reads it, and `SourceIndex` answers only when it is absent — a link that has not reached the Mac, or a material prepared before the field existed. The live page knows the section above the article and `og:site_name`; the app only has a catalog snapshot, which is the weaker answer and stays a fallback.

Rejected: dropping `publisher_of` (loses the live page's section and `og:site_name`); keeping both as peers (two answers that can disagree).

## 3. The title of a material

**Decided: one server function, and the app only reads `material.title`.** The order is the owner's: the page's `<title>` without the site name it ends with, then the first heading of the Markdown, then the address it came from. `page_title` already strips a trailing `" – site"`; `first_heading` already reads the first `# ` line. The adapters stop choosing; the tile and the reader show the same name because both read the package.

Rejected: the first Markdown heading first (a page whose heading is an image loses its name); four fallback orders (the title depends on which branch found the article).

## 4. The delivery file name

**Decided: the material id everywhere.** `package.delivery_name(material_id)` is the one rule; the prepare script names a link archive `delivery_name("link:<url>")` and an article archive `delivery_name(stable_id("article", url))`. Old prepared files keep their names because the app stores the name it read; a link archive and its later article archive are two files with two ids, and the app removes the link's when the article replaces it.

Rejected: the URL everywhere (a redirect moves the name under the material; links that differ by fragment already share a material).

## Cost of the decided set

| Choice | New code | Deleted code | Risk |
|---|---|---|---|
| 2 server canonical | ~6 lines (a `declaredSource` and two call sites) | the path heuristic later | low: old materials keep the fallback |
| 3 one title function | ~10 lines | the second order in `_document_package` | medium: `<title>` can be generic ("Home") |
| 4 id names | ~10 lines in the prepare script | the URL hash | low: old files keep their names |
| 1 keep apart | 0 | 0 | low: two tables, by design |

The order in 3 is a taste call, not a logical one: a page whose `<title>` is generic and whose first heading is the real name would now be named "Home". The fix, if it happens, belongs in `page_title` (drop a title that equals the site name), not in a second order.
