# Naming: finding a better name than "MacDring"

> **Decision (July 2026): the app is now Top Drawer.** The finalists were Top
> Drawer and Corner Store; Corner Store was eliminated on clearance (existing
> CornerStore apps on the App Store, plus the convenience-retail POS category
> owning the phrase in search) and on accuracy (the app lives on edges, not
> corners). Phase 1 of the rename — everything user-visible — is done; the
> remaining machinery is listed at the bottom of this file.

The current name has problems worth fixing:

- **It doesn't say anything.** "Dring" reads as a typo or a doorbell sound; nothing
  in the name hints at edge tabs, drawers, or launching.
- **The "Mac" prefix is dated.** Modern Mac apps almost never carry it (compare
  Raycast, Yoink, Bartender, Ice) — the platform is implied by where the app runs.
- **It's awkward to say out loud** and hard to remember after hearing it once.

## What a good name needs

1. **Evokes the core idea** — things tucked at the screen edge that slide out when
   you need them (tabs → drawers → your stuff).
2. **One or two words, pleasant to say**, works bare as `Name.app` without a "Mac"
   prefix.
3. **No collisions** with existing Mac apps — especially not in the
   dock/launcher/shelf category — and no famous trademark in an adjacent space.
4. **Searchable**: "«name» mac app" should be winnable.
5. Bonus: keeps a little of DragThing's playful, physical-object spirit.

## Candidates vetted (July 2026)

Every name below was checked against the Mac App Store, indie Mac app sites, and
general web search.

### Eliminated — direct collisions

| Name | Why not |
|---|---|
| Alcove | Well-known Mac "Dynamic Island" app (tryalcove.com) |
| Pegboard | MonoTools menu-bar command center for Mac |
| Sideboard | MTG app + a meetings menu-bar app; also confusable with "Sidebar", an existing dock replacement |
| Cubby | LogMeIn's (dead) sync product, plus several active projects |
| Sill | At least three current apps (link aggregator, social app, plant game) |
| Tuck | Two current Mac apps — one literally docks windows to screen edges |
| Berth | Current open-source Mac container GUI |
| Quay | Rainer Brockerhoff's classic Dock extender — dead, but same category |
| Wharf | A macOS **adware** family; the web is full of "remove Wharf.app" guides |
| Tansu | Kafka broker (tansu.io), document tool (tansu.co), Mac synth |
| Jetty | Eclipse Jetty web server owns the word for developers |
| Dovetail | Large research SaaS (dovetail.com) |
| Shelf / Dockside / Sidebar | All existing Mac shelf/dock apps |

### Shortlist — clean names, ranked

#### 1. Top Drawer  ⭐ recommended

The top drawer is where you keep the things you reach for constantly — which is
exactly what this app is. And **"top-drawer" is an idiom meaning first-rate**, so
the name compliments itself. It is warm, physical, and a little wry — the same
register DragThing lived in.

- No Mac app of this name exists (verified July 2026); nearest neighbors are
  "Drawers" (drawers.computer, a project-workspace switcher — different category)
  and Google's dormant 2009 "Top Draw" wallpaper generator.
- Reads naturally in every UI string: *"Top Drawer Settings…"*, *"New Items Tab"*,
  menu bar tooltip "Top Drawer".
- Tagline options: *"Your Mac, top drawer."* / *"Everything you reach for,
  right at the edge."*
- Bundle/product name `TopDrawer`, display name "Top Drawer".

#### 2. Bureau

A bureau *is* a chest of drawers (and a writing desk). One elegant word, zero Mac
app collisions found. Downsides: FBI/government connotation in the US, lots of
design agencies named "Bureau", and a generic dictionary word is harder to win in
search than a two-word phrase.

#### 3. Hutch

A hutch is a cabinet with shelves that sits against a wall — short, friendly,
slightly quirky. No Mac app collision. Downsides: "Hutch" is a major Hutchison
telecom brand in Asia, and the rabbit-cage reading arrives first for many people.

#### 4. Credenza

Furniture that stands against the wall and holds your things — precisely the
metaphor. Zero software collisions at all. Downsides: four syllables, a touch
formal, harder to type.

### Honorable mention

- **DrawerThing** — the maximal DragThing homage (drawers + Thing). Guaranteed to
  make old DragThing users smile, but it's derivative and "…Thing" names read as
  90s-shareware today. Kept here in case sentiment should win.

## Other models' shortlists, vetted

**GPT 5.6** (the July 2026 review's naming pass) proposed coined portmanteaus:
Drawledge, Brimfold, ScreenSill, Ledgelet, Railnook, Tabstead, Drawrail, Screenstead,
Selvedge, Corner Store. Verified clean: Drawledge and Brimfold (nothing but a dormant
blog and a knitting pattern). But the coinages mostly repeat MacDring's core flaw —
invented mashups that mean nothing until explained — and the only existing use of
"Drawledge" online is a *drawing* blog, confirming it misreads as a sketching app.
Best of the list: **Drawledge** (with that caveat), **Brimfold** (clean but
abstract), Corner Store (most human, but the app lives on edges, not corners). Its
wider sweep had already rejected as crowded/colliding: Railnest, Tabloom, Brimlet,
Tabinet, Edgeward, Sidefold, SideKeep, Railkeep, Tuckrail, Drawlet, Rimfold, Taboret,
and Sidelatch.

**GLM 5.2** proposed real words with physical imagery: Edgeways, Fringe,
Verge/Brink, Tether, Latch, Sleeve, Tray, Holster, Cubby/Nook, Pier, Quay/Wharf,
Mooring, Caddy, Stash. Best ear of the three explorations, but no clearance was
done and most entries collide:

| Name | Status |
|---|---|
| Pier | ❌ "App Pier" (Mac keyboard launcher — same category) + "Pier" menu-bar monitor |
| Latch | ❌ Latch Systems trademark covers software design/development + smart home |
| Sleeve | ❌ Popular Replay Software now-playing Mac app |
| Quay / Wharf / Cubby | ❌ Already eliminated above (Wharf is macOS adware) |
| Tether | ❌ The stablecoin owns the word |
| Verge / Nook / Caddy / Stash / Tray / Brink / Fringe | ❌/⚠️ The Verge, B&N Nook, Caddy server, Stash investing + git stash, system-tray genericism, Brink's, Fox's Fringe |
| **Edgeways** | ✅ No exact collision — the survivor, and a genuine contender |

**Edgeways** is the one outside suggestion worth shortlisting: a real word meaning
exactly what the app does, with the "get a word in edgeways" idiom. Caveats: US
English says *edgewise* (a taken name — Edgewise card game, EdgeWise Connect,
edgewise.app domain squatted), so half the audience types the wrong, occupied
spelling; and the Edge* software neighborhood is crowded (Microsoft Edge, Edgy,
EdgeView).

## Updated overall ranking

1. **Top Drawer** — real phrase, names the UI, built-in quality pun, clean.
2. **Edgeways** (GLM) — real word, names the placement, clean in the strict sense;
   dinged for the edgewise-spelling split and the Edge* crowd.
3. **Brimfold** (GPT) — cleanest coined option if an abstract brand is preferred.
4. **Bureau / Hutch / Credenza** — clean furniture words, each with a caveat above.
5. **Drawledge** (GPT) — most characterful coinage; misreads as a drawing app.

## Recommendation

**Top Drawer.** It is the only candidate that scores on all five criteria: it
names the app's literal UI (drawers), carries a built-in quality pun, has no
collisions, is easy to say and search, and keeps the playful physical-object
spirit of DragThing without borrowing its letters.

Before committing to it: spend 10 minutes on a trademark screen (USPTO TESS /
Swissreg) and grab a domain — `topdrawer.app` or a `get…`/`use…` variant.

## Rename status

### Phase 1 — done (this branch)

- `CFBundleDisplayName` → "Top Drawer" (About panel, menu bar, Finder display).
- `NSAppleEventsUsageDescription` and every user-facing string in the app —
  menus ("Quit Top Drawer", "Top Drawer Settings…"), Settings, alerts, the
  welcome note, export panel default filename, updater dialogs (`appName` is
  display-only; assets are matched by extension, verified).
- All source comments and log prefixes; README, AGENTS.md, docs/.

### Deliberately unchanged, with reasons

- **Bundle ID `com.macdring.MacDring`** — changing it resets user defaults,
  saved layouts, and Automation/permission grants. Keep, or ship a migration.
- **Application Support directory `MacDring/`** (`TabStore.defaultStoreURL`) —
  renaming orphans every user's saved layout. Keep, or migrate on launch.
- **Updater `repo: "MacDring"`** — must match the GitHub repo until it's renamed.
- **Code identifiers** (`RecentsSource.macDring`, `includesMacDring`,
  `MacDringMain`) — `.macDring` is a persisted raw value in saved documents;
  the others aren't worth an unverifiable refactor. Rename only with Xcode.
- **Frame autosave name `MacDringSettingsWindow`** — a defaults key.

### Phase 2 — done (this branch)

- `PRODUCT_NAME = "Top Drawer"` — the built app is now **Top Drawer.app** —
  with both `TEST_HOST` paths and the shared scheme's `BuildableName` updated
  in lockstep.
- Release pipeline: `APP_NAME: "Top Drawer"` (display), `ASSET_BASE: TopDrawer`
  (zip/dmg filenames, space-free because GitHub rewrites spaces in asset names
  to dots), quarantine command quoted for the space. Old installed clients
  still self-update fine — the updater picks assets by extension, not name.
- `scripts/build.sh` / `scripts/release.sh` stubs export the new app name
  (verify the shared `lkm-build`/`lkm-release` engine quotes `$APP_NAME` —
  the name now contains a space).
- App icon — the "open wooden drawer of glowing app tiles" artwork
  (`Tools/AppIcon-source.png`, slots regenerated per `Tools/README.md`).

### Phase 3 — remaining, needs actions outside this repo

1. Rename the GitHub repo to `top-drawer` (old URLs redirect), then update the
   updater's `repo:` in `AppDelegate.swift` and the README release links.
2. Cosmetic (optional, needs Xcode open): rename the project file, targets,
   schemes, and `MacDring/` source folders. Purely developer-facing.
3. New screenshot for the README showing the renamed app.
4. Domain + trademark: `topdrawer.app` (or `get…`/`use…` variant), quick
   USPTO/Swissreg screen.
5. First release under the new name: verify the Release workflow end-to-end
   (it now builds "Top Drawer.app" and uploads `TopDrawer-<v>.zip/.dmg`) and
   mention "formerly MacDring" in the release notes once.
