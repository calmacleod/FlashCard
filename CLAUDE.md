# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Start development server (requires Ollama running separately)
bin/rails server

# Run all tests
bin/rails test

# Run a single test file
bin/rails test test/models/rulebook_entry_test.rb

# Run a single test by line number
bin/rails test test/models/rulebook_entry_test.rb:12

# Database setup / migrations
bin/rails db:create db:migrate

# Lint (RuboCop with Rails Omakase style)
bundle exec rubocop

# Job queue UI
# Visit /jobs in browser (MissionControl::Jobs)
```

## Architecture Overview

This is a Rails 8 app for processing rulebook PDFs into structured, searchable entries with an AI-powered rule agent. The pipeline is:

**Upload PDF → Process → Index → Search / Chat with Agent**

### Processing Pipeline

1. User uploads a rulebook PDF via `RulebookController`
2. `RulebookProcessor` extracts and structures rules from the PDF using RubyLLM (`gemini-2.5-flash`)
3. The pipeline normalizes and assembles `RulebookEntry` and `RulebookChunk` records
4. `RuleIndexer` indexes entries for search
5. Users can search rules via `RuleSearchController` or chat with the `RuleAgentController`
6. The rule agent (`RuleAgentJob`) uses tools (`RuleSearchTool`, `RuleDefinitionLookupTool`, `RuleReferenceLinkTool`) to answer questions

### Key Models

- **`RulebookEntry`** — a structured rule entry extracted from the PDF
- **`RulebookChunk`** — a semantic chunk of a rulebook PDF
- **`Chat`** — a chat conversation with the rule agent
- **`Message`** — an individual message in a chat conversation
- **`ToolCall`** — a tool invocation made by the agent
- **`Model`** — LLM model selection/configuration

### LLM Integration

**`OllamaClient`** — wraps Ollama's HTTP API directly. Two main methods:
- `#generate` — `/api/generate` endpoint
- `#chat` — `/api/chat` with optional JSON schema `format` parameter

**RubyLLM** (`ruby_llm` gem) is configured in `config/initializers/ruby_llm.rb`. It connects the `:openai` provider to Ollama's OpenAI-compatible endpoint AND to Gemini (via `GEMINI_API_KEY`). The `RUBYLLM_PROVIDER` env var controls which provider is active. The rulebook pipeline uses RubyLLM with `gemini-2.5-flash`.

### Services (`app/services/`)

| Service | Responsibility |
|---|---|
| `OllamaClient` | HTTP wrapper for Ollama API |
| `RulebookProcessor` | PDF → structured rule units via RubyLLM |
| `RulebookPipeline` | Orchestrates the full rulebook processing flow |
| `RulebookAssembler` | Assembles processed chunks into entries |
| `RulebookNormalizer` | Normalizes rule text |
| `RulebookReviewer` | Reviews/validates extracted rules |
| `RulebookFlashcardGenerator` | Generates flashcards from rulebook entries |
| `RulebookAnkiTagger` | Tags entries for Anki export |
| `RuleAgent` | AI agent that answers rule questions using tools |
| `RuleSearchTool` | Tool for searching rules |
| `RuleSearcher` | Underlying search implementation |
| `RuleDefinitionLookupTool` | Tool for looking up rule definitions |
| `RuleReferenceLinkTool` | Tool for resolving rule references |
| `RuleIndexer` | Indexes rulebook entries for search |

### Background Jobs

All jobs use Solid Queue. The job dashboard is at `/jobs` (MissionControl::Jobs).

- **`RuleAgentJob`** — async rule agent processing

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
