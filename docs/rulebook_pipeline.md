# Rulebook Pipeline

`RulebookPipeline` is an interactive command-line orchestrator that converts a raw rulebook PDF into structured `RulebookEntry` database records, ready for search and flashcard generation. It runs three sequential steps, prompting the user for configuration at each one.

---

## High-Level Flow

```
PDF file on disk
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│  Step 1 — PROCESS                                       │
│  RulebookProcessor                                      │
│  PDF → text → chunks → LLM extraction → RulebookChunks │
└───────────────────────────┬─────────────────────────────┘
                            │  RulebookChunk records (DB)
                            ▼
┌─────────────────────────────────────────────────────────┐
│  Step 2 — ASSEMBLE                                      │
│  RulebookAssembler                                      │
│  RulebookChunks → resolve context → CSV file           │
└───────────────────────────┬─────────────────────────────┘
                            │  <rulebook_name>.csv
                            ▼
┌─────────────────────────────────────────────────────────┐
│  Step 3 — NORMALIZE                                     │
│  RulebookNormalizer                                     │
│  CSV rows → (LLM or direct) → RulebookEntry records    │
└───────────────────────────┬─────────────────────────────┘
                            │
                            ▼
                  RulebookEntry records (DB)
```

---

## Running the Pipeline

```ruby
RulebookPipeline.run("path/to/rulebook.pdf")
```

The pipeline is fully interactive — it prints banners and prompts at each step, then delegates to the relevant service.

---

## Step 1 — Process PDF into Chunks

**Service:** `RulebookProcessor`

### What happens

1. **Text extraction** — `pdftotext` pulls raw text from the PDF.
2. **Boilerplate stripping** — a set of regexes removes:
   - Running page headers (e.g. `"Chapter Title   Rule 2 Section 1 Article 3"`)
   - Chapter title blocks
   - Page numbers
   - Footer lines (e.g. `"Canadian Amateur Rule Book for Tackle Football   42"`)
   - Casebook cross-references (e.g. `(CB42)`)
3. **Chunking** — the cleaned text is split into manageable pieces. Chunks are bounded by structural headings:

   | Boundary | When it triggers |
   |---|---|
   | `Rule N –` heading | Always — hard boundary |
   | `Section N:` heading | Always — hard boundary |
   | `Article N` heading | Only when the current chunk is already ≥ ~400 words |
   | Hard word cap | When a paragraph would push the chunk over `max_words` |

   Target chunk size is 700–1,000 tokens (~467–667 words).

4. **DB persistence** — each chunk is saved as a `RulebookChunk` record with `status: "pending"`. If chunks already exist for this PDF path they are reused (incremental/resumable).

5. **User confirmation** — the processor previews all chunks and asks:
   - `y` — proceed with LLM extraction
   - `n` — abort
   - `c` — clear existing chunks and abort

6. **LLM extraction** — each pending chunk is sent to the configured Gemini model with a structured schema prompt. The LLM returns a JSON array of `Unit` objects:

   ```json
   {
     "units": [
       {
         "rule_number": "Rule 1 – The Field",
         "section":     "Section 2: Goal Posts",
         "article":     "Article 3 – Height",
         "text":        "The goal posts shall be..."
       }
     ]
   }
   ```

   Completed chunks are cached in the DB — re-running skips them.

### Chunking diagram

```
Raw PDF text
     │
     ▼  strip boilerplate (headers, footers, page numbers)
     │
     ▼  ensure_section_breaks (inject \n\n before Section headings)
     │
     ▼  split into paragraphs
     │
     └─► for each paragraph:
             Rule heading?    ──► flush buffer, start new chunk
             Section heading? ──► flush buffer, start new chunk
             Article heading  ──► flush if chunk already ≥ 400 words
             otherwise        ──► append to buffer
     │
     ▼
  chunks[] → persisted as RulebookChunk records
```

### Prompts collected

| Prompt | Default |
|---|---|
| Processor model | `gemini-3-flash-preview` |
| Delay between chunks (seconds) | `0` |

---

## Step 2 — Assemble Chunks into CSV

**Service:** `RulebookAssembler`

### What happens

1. Loads all `completed` `RulebookChunk` records for the PDF (optionally filtered to a chunk index range).
2. **Context resolution** — walks every unit in chunk order, maintaining a running `current_rule / current_section / current_article` context. When a higher-level heading appears it resets the lower levels (e.g. a new Rule clears the current Section and Article). This means units that only have partial headings still receive the full hierarchical context from earlier chunks.
3. **Article heading promotion** — if a unit's text begins with an inline article heading (e.g. `"Article 4 – Ball in Play\n…"`), it is promoted to the `article` field and stripped from the body text to avoid duplication.
4. Writes a CSV to `<Rails.root>/<stem>.csv` with columns: `chunk`, `rule_number`, `section`, `article`, `text`.

### Context carry-forward diagram

```
chunk 0: { rule: "Rule 1", section: nil, article: nil, text: "" }
   │  → sets current_rule = "Rule 1"
chunk 0: { rule: nil, section: "Section 1", article: nil, text: "..." }
   │  → sets current_section = "Section 1"
   │  → resolved: rule="Rule 1", section="Section 1", article=nil
chunk 1: { rule: nil, section: nil, article: "Article 2", text: "..." }
   │  → sets current_article = "Article 2"
   │  → resolved: rule="Rule 1", section="Section 1", article="Article 2"
chunk 1: { rule: "Rule 2", section: nil, article: nil, text: "" }
   │  → new rule → resets section + article to nil
   ...
```

### Prompts collected

| Prompt | Default |
|---|---|
| Start from chunk index | (none — all) |
| End at chunk index | (none — all) |
| Show chunk boundaries in output? | `N` |

---

## Step 3 — Normalize into RulebookEntry Records

**Service:** `RulebookNormalizer`

### What happens

1. Reads the CSV produced in Step 2.
2. Clears any existing `RulebookEntry` rows for this CSV path.
3. Groups all rows by `rule_number`.
4. For each rule group, one of two paths is taken:

#### Path A — LLM Normalization (default)

Each rule group (all CSV rows for one Rule) is sent to a Gemini model with surrounding context (the tail of the preceding chunk's text and the head of the following chunk's text). The LLM is asked to:

- Standardise heading casing and punctuation
- Merge consecutive rows belonging to the same section/article
- Infer and fill missing section or article labels
- Correct hierarchy mismatches
- Preserve all meaningful text

The returned units are written to `RulebookEntry` records.

#### Path B — Direct Import (skip LLM)

Walks the CSV rows in order, carrying forward `rule / section / article` context the same way the assembler does. Rows that have a rule but no section or article context yet are skipped (they are bare rule headings). All other rows are written directly to `RulebookEntry` records.

### Normalization paths diagram

```
CSV rows grouped by rule_number
          │
          ├─── direct: true ──────────────────────────────┐
          │                                               │
          │  carry forward rule/section/article context   │
          │  write row → RulebookEntry                    │
          │                                               │
          └─── direct: false (default) ──────────────────┘
                    │
                    ▼  for each rule group:
                    │
                    │  build prompt:
                    │    - all rows for this rule
                    │    - tail of preceding chunk (context)
                    │    - head of following chunk (context)
                    │
                    ▼  LLM (gemini-2.5-flash)
                    │
                    ▼  structured JSON → units[]
                    │
                    ▼  write each unit → RulebookEntry
```

### Prompts collected

| Prompt | Default |
|---|---|
| Skip LLM and carry forward context directly? | `N` |
| Normalizer model (if not direct) | `gemini-2.5-flash` |
| Delay between groups (seconds) | `0` |

---

## Database Records

| Record | Created by | Purpose |
|---|---|---|
| `RulebookChunk` | Step 1 | Stores raw chunk text and LLM-extracted units JSON; cached for reruns |
| `RulebookEntry` | Step 3 | Final normalised, structured rule entries used by the rest of the app |

---

## Resumability

- **Step 1** is idempotent per PDF path. If `RulebookChunk` records already exist for a path, they are reloaded. Completed chunks are skipped; only `pending` or `failed` chunks are re-processed.
- **Step 3** clears and rewrites all `RulebookEntry` records for the CSV path on every run.

---

## Key Constants (RulebookProcessor)

| Constant | Value | Purpose |
|---|---|---|
| `TARGET_MIN_TOKENS` | 700 | Minimum chunk size before splitting at Article boundaries |
| `TARGET_MAX_TOKENS` | 1000 | Target upper bound for chunk size |
| `MAX_TOKENS` | 1200 | Hard cap (applied if `max_tokens:` option is set) |
| `CONTEXT_WORDS` | 400 | Words of surrounding chunk text sent to the normalizer as context |
