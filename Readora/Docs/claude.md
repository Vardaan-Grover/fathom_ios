# 🧠 Project Context: AI-Powered iOS Reading Companion

## 1. Project Overview & Philosophy
We are building a context-aware reading engine for iOS that enhances the reading experience without breaking immersion. 

**The Core Problem:** Readers lose flow when looking up vocabulary, lacking contextual understanding, or switching to external tools (which either lack book-specific context or provide static annotations).
**The Solution:** A hybrid AI engine that builds a **Narrative Memory Graph** (entities + events) of the entire book, providing instant, accurate, and spoiler-free explanations.

**Product Philosophy:**
* **What it IS:** A reading accelerator, a context provider, and a tool to maintain flow.
* **What it is NOT:** A replacement for critical thinking, a simple summary machine, or a "cheat tool."

---

## 2. High-Level Architecture & Stack
We use a **Hybrid AI Architecture** to balance performance, cost, and device constraints.

* **iOS App (Frontend & Local Logic):** Swift, SwiftUI
* **Local Persistence:** GRDB (SQLite), using `async/await` + Actors
* **EPUB Parsing:** Readium
* **Backend:** Handles chunk processing, parallel LLM execution, caching, and runtime Q&A.
* **Context Assembly:** Hybrid (Local retrieval + Backend LLM generation)

---

## 3. Core Data Models & Schema Rules

### 🚨 Critical Schema Constraints
* **NO Character Offsets (`charStart` / `charEnd`):** LLMs are highly unreliable at calculating exact string offsets.
* **Paragraph-Based Grounding ONLY:** Every entity and event must be strictly tied to paragraph ranges.

### Core Entities
* **Structure:** `Chapter`, `Paragraph`
* **Entities:** `NarrativeEntity` (Characters, Places, Organizations), `NarrativeEntityMention`
* **Events (The Core Engine):** `NarrativeEvent` (Meaningful story developments, actions, decisions)
    * Fields: `firstParagraphID`, `lastParagraphID`, `summary`, `participantEntityIDs`

---

## 4. Processing Pipeline

### PHASE A: Ingestion & Preprocessing (Background)
*UX Note: The user can start reading immediately while this runs in the background, observing an `aiAnalysisProgress` indicator.*

1.  **EPUB Parsing (Local):** Readium extracts Chapters and Paragraphs. Assigns `absoluteIndex` and `chapterID`. Stores in SQLite.
2.  **Chunking:** Split paragraphs into sequential chunks (5–10 paragraphs). Include a read-only **Context Prefix** (last 2–3 paragraphs from the previous chunk) to prevent lost context at chunk boundaries.
3.  **Event Extraction (Backend LLM):** Process chunks to extract `NarrativeEvent` data.
4.  **Entity Extraction (Backend LLM):** Run a parallel pipeline to extract names and mentions (`NarrativeEntity`, `NarrativeEntityMention`).
5.  **Global Entity Reconciliation (Backend LLM):** After all chunks process, group duplicate character mentions into canonical identities (e.g., "Darcy", "Mr. Darcy" → unified `Fitzwilliam Darcy`).
6.  **Persistence:** Store all Events and Entities in the Backend, cache per book, and sync back to the user's Local GRDB.

### PHASE B: Runtime Context Engine (User Interaction)
1.  **Trigger:** User highlights text or asks a question.
2.  **Context Retrieval (Local SQLite):**
    * **🚨 STRICT SPOILER PREVENTION:** `WHERE lastParagraphID <= currentParagraphID`
    * Retrieve past events ranked by recency and importance.
    * Retrieve relevant entities currently in context.
3.  **Context Assembly:** Construct the LLM prompt using: `[USER QUESTION] + [RELEVANT PAST EVENTS] + [RELEVANT ENTITIES] + [CURRENT PARAGRAPH]`.
4.  **Backend LLM Call:** Generate a concise, context-aware, spoiler-free explanation.

### PHASE C: "Chat with Entire Book" Mode
* **Trigger:** User asks a global question.
* **Execution:** Retrieve the top relevant events across the entire book + entity summaries. Send to Backend LLM.
* **Constraint:** Do *not* send the entire book text. Strictly use retrieval + summarization.

---

## 5. 🛑 "Do Nots" & Architectural Guardrails
To ensure project success, strictly avoid the following:

1.  **NO Overlapping Chunk Merging:** Use sequential chunks with a context prefix instead of writing complex post-merge logic.
2.  **NO Full-Book LLM Ingestion:** Always use chunk-based processing and targeted retrieval to optimize tokens and costs.
3.  **NO Real-Time Chunk Processing on Device:** Defer heavy extraction to the backend async job system.
4.  **NO Scene Extraction:** Stick to `NarrativeEvents`. Overly granular scene logic introduces unnecessary complexity at this stage.
5.  **NO Heuristic-Only Systems:** Rely on the structured Narrative Memory Graph.

**The Final Vision:** The product succeeds through structured narrative understanding (events + entities) paired with strict temporal filtering, resulting in the first truly context-aware, seamless reading engine.