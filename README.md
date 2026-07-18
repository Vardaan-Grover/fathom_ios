# Fathom

an iOS reading app i've been building cuz i got tired of every other utilitarian ebook app treating books like bland documents to gawk at. i'm talking to you: kindle & apple books.

## **what even is fathom?**

Fathom is an EPUB reader for iPhone. that's the boring one-line version. the actual point of it is that reading on your phone/ipad has felt kind of dead for a while now. you open an app, scroll through a grid of book covers, pick one, read through it, and then you're off to the next one on the list. no personality, no sense that anything happened while you were reading.

so Fathom is my attempt at fixing that. some of the stuff that it does includes:

- **a glass shelf library:** your books actually sit on a glass shelf, with the ability for you to choose your own book covers for the book you're reading. apple had this wooden shelf type isomorphic design in iBooks and then killed it in like 2013 for some reason and nobody brought it back. well it's back in a more pinterest-y way now
- **an actual reader** — clean epub reading, themes, the normal stuff you'd expect but done properly (fonts, margins, real pagination, doesn't feel like a webpage in a wrapper)
- **an AI reading companion, opt-in per book** — turn it on for a specific book and you can straight up ask it questions about what you just read, get context on characters/plot, whatever you're confused about. it's per-book on purpose, not some app-wide chatbot bolted on. if you never turn it on for a book, Fathom never even talks to a server about that book, it's 100% local. i'm still a little hazy on exactly how deep i want this one to go though
- **contextual word lookup + save** — tap a word while reading and it pulls up the dictionary definitions. tap the little sparkles icon and it figures out which of those definitions actually fits the sentence you were reading, using an embedding model that runs fully on-device, so your sentence never leaves your phone for that part. save whichever word to your own vocabulary collection for later
- **cross-book notes** — every note and highlight you make, across every book, lives in one place you can flip back through. so it's not "this book's notes" trapped inside that book forever, it's more like a running notebook of everything you've read
- **iCloud sync** — your whole library, reading progress, notes, vocab, all of it syncs across your devices through iCloud. so your phone and ipad are always looking at the same shelf
- **a proper "you finished the book" moment** — most apps just close the book and move on. Fathom pauses for a sec, lets you rate it, write a lil reflection, even attach a photo if you want. finishing a book should feel like something and i've tried making it special in fathom through these small rituals

### **the thing i'm most hyped about**

it's called the "sky." every day you read, it adds a hand-drawn doodle to a personal star-chart type grid. bigger reading sessions = bigger/rarer doodles (comets, constellations, actual planets), short sessions get little sparks and stars. it's basically a whole personal night sky made entirely out of your reading history, no streak-shaming, no red numbers, just a sky that slowly fills in. also a cool fact, none of the doodles used in the app are AI generated. my best friend literally drew them all on her iPad with her pencil. i think it's one of the coolest features of the app. i love it.

## **why i'm building this**

honestly i just wanted reading on my phone to feel like something warm and personal again instead of just a productive activity to be doing. i kept using ebook apps that treated a book the exact same way they treated a pdf or a work doc — no warmth to any of it. books deserved better than a grid and a progress bar. so i started building the app i actually wanted to use, and it kinda turned into this.

i wanted everything to feel personal (not perfect). ngl though during some areas i did get lil stuck up. for eg: i spent way too much time getting the glass shelf to actually look like glass lol. probably more time than was reasonable for a library screen. plus the doodle point that i already talked about.

## **the tech part**

not gonna pretend this readme is just vibes, here's actually what's under the hood:

- **Swift + SwiftUI** for basically the whole app, no UIKit unless i absolutely have to
- **GRDB** (sqlite) for local storage: the device is the source of truth for your whole library
- **Readium Swift Engine** for actually rendering epubs: pagination, themes, annotations, all that
- **CloudKit** powers the iCloud sync — a proper sync engine that pushes/pulls your library, notes, and vocab across devices
- a bundled **Core ML embedding model** (bge-small) is what runs the contextual word ranking on-device — no server involved for that one
- a **ContextEngine** that only kicks in for AI-enabled books: handles the upload/ingestion/query flow to the backend so the AI companion can actually answer questions about your book (the code is there but i'm still a little iffy about whether to implement this in the app or not)
- backend only exists to power the AI stuff (upload to storage, a processing pipeline, then you can query it). it's not involved in anything else, which was a deliberate call so the core reading experience never depends on internet or a server being up (since the ai features are not an active part of the UI right now, the backend is not being utilized yet)
- codebase is split out roughly by layer: Data / Domain / Presentation / Services / UI

it's a solo project, built mostly late at night between school stuff. most of the app (library, reader, notes, vocab, sync, completion) is solid and working, the sky is the current big thing i'm building out.