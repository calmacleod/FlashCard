# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Start development server (requires Ollama running separately)
bin/rails server

# Run all tests
bin/rails test

# Run a single test file
bin/rails test test/models/flash_card_test.rb

# Run a single test by line number
bin/rails test test/models/flash_card_test.rb:12

# Database setup / migrations
bin/rails db:create db:migrate

# Lint (RuboCop with Rails Omakase style)
bundle exec rubocop

# Job queue UI
# Visit /jobs in browser (MissionControl::Jobs)
```

## Architecture Overview

This is a Rails 8 app that turns uploaded PDFs into Anki-compatible flashcard sets using local LLMs via Ollama. The pipeline is:

**Upload → Chunk → Approve → Generate → (Refine) → Export CSV**

### Processing Pipeline

1. User uploads a PDF on `FlashCardsController#create`
2. `FlashCardChunkingJob` runs: extracts text via `PdfTextExtractor`, then `SemanticChunker` asks the LLM to produce a structured outline with line-number boundaries, then slices the text into `FlashCardChunk` records
3. Status moves to `awaiting_approval` — user reviews/edits chunks in the UI, then submits `approve_chunks`
4. `FlashCardGenerationJob` runs: iterates approved chunks, sends each to `OllamaClient#generate` via `FlashCardPromptBuilder`, parses card pairs via `FlashCardCardsExtractor`, saves `FlashCard` records
5. Optional: `FlashCardRefinementJob` re-evaluates each card against a user instruction via `FlashCardRefinementPromptBuilder` + `FlashCardDecisionParser`, marking each card `kept`/`changed`/`discarded`
6. Completed cards export as CSV (Anki-compatible, two-column: front, back)

### Key Models

- **`FlashCardRequest`** — the central record tracking a PDF job; holds status, progress, log, model choice, detail level. Statuses: `queued → chunking → awaiting_approval → processing → refining → completed / failed`
- **`FlashCardChunk`** — a semantic slice of the PDF, with `approved` flag, `path_json` (breadcrumb array), and `content_text`
- **`FlashCard`** — a generated card with `front`/`back` plus optional refinement fields (`refined_front`, `refined_back`, `status`: kept/changed/discarded). `effective_front`/`effective_back` return the correct value based on refinement status

### Real-time Updates

After every `FlashCardRequest` save, `FlashCardRequestBroadcaster` re-renders the `flash_cards/request_panel` partial and broadcasts it over Action Cable channel `flash_card_request:<id>`. The front-end Stimulus controller subscribes and swaps in the HTML.

### LLM Integration

**`OllamaClient`** — wraps Ollama's HTTP API directly (not via RubyLLM). Two main methods:
- `#generate` — legacy `/api/generate` endpoint
- `#chat` — `/api/chat` with optional JSON schema `format` parameter (used by `SemanticChunker` for structured outline output)

**RubyLLM** (`ruby_llm` gem) is configured in `config/initializers/ruby_llm.rb`. It connects the `:openai` provider to Ollama's OpenAI-compatible endpoint AND to Gemini (via `GEMINI_API_KEY`). The `RUBYLLM_PROVIDER` env var controls which provider is active. RubyLLM is available for new AI features but the existing pipeline uses `OllamaClient` directly.

### Services (`app/services/`)

| Service | Responsibility |
|---|---|
| `OllamaClient` | HTTP wrapper for Ollama API |
| `SemanticChunker` | AI-driven outline → line-slice chunks |
| `PdfTextExtractor` | PDF → text with `<<<PAGE N>>>` markers |
| `PdfVectorizer` | Embedding generation (via Ollama) |
| `PdfChunker` | Simpler non-AI chunking (legacy) |
| `FlashCardPromptBuilder` | Builds generation prompts |
| `FlashCardCardsExtractor` | Parses LLM response → card pairs |
| `FlashCardRefinementPromptBuilder` | Builds refinement prompts |
| `FlashCardDecisionParser` | Parses keep/change/discard decisions |
| `FlashCardRequestBroadcaster` | Action Cable broadcast helper |

### Background Jobs

All jobs use Solid Queue. The job dashboard is at `/jobs` (MissionControl::Jobs).

### Environment Variables

| Variable | Purpose |
|---|---|
| `GEMINI_API_KEY` | Gemini API key (required for RubyLLM Gemini provider) |
| `RUBYLLM_PROVIDER` | Active RubyLLM provider (`gemini` or `openai`) |
| `OLLAMA_API_BASE` | Ollama base URL (default: `http://localhost:11434/v1`) |
| `OLLAMA_GENERATION_MODEL` | Default model for generation |
| `OLLAMA_EMBEDDING_MODEL` | Default embedding model (default: `nomic-embed-text`) |
| `OLLAMA_READ_TIMEOUT` | HTTP read timeout in seconds (default: 300) |

### Database

SQLite with four schemas: main app (`db/schema.rb`), plus separate schemas for Solid Queue (`db/queue_schema.rb`), Solid Cache (`db/cache_schema.rb`), and Solid Cable (`db/cable_schema.rb`).

PDFs are stored in `storage/uploads/` with a random hex prefix.

### Ruby Version

Ruby 3.4.7 (`.ruby-version`). The `mise.toml` specifies 4.0.1 — use `.ruby-version` as the source of truth.
