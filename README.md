# FlashCard

A Rails 8 app that turns uploaded PDFs into Anki-compatible flashcard sets using local LLMs via Ollama (or Gemini/ChatGPT).

## How it works

1. Upload a PDF
2. The app extracts text and uses an LLM to semantically chunk it into logical sections
3. Review and approve the chunks
4. Cards are generated for each chunk
5. Optionally refine cards with a custom instruction (keep/change/discard)
6. Export as a two-column CSV ready for Anki import

## Requirements

- [Mise](https://mise.jdx.dev/) — manages Ruby version
- [Ollama](https://ollama.com/) — local LLM inference (or Gemini via API key)
- `poppler` — for PDF text extraction (`pdftotext`)
  ```bash
  brew install poppler   # macOS
  ```

## Setup

```bash
# Install Ruby via mise
mise install

# Install gems
bundle install

# Create and migrate the database
bin/rails db:create db:migrate

# Copy environment variables template and fill in values
cp env.template .env
```

### Environment variables

| Variable | Purpose |
|---|---|
| `GEMINI_API_KEY` | Gemini API key (required if using Gemini) |
| `OLLAMA_API_BASE` | Ollama base URL (default: `http://localhost:11434/v1`) |
| `OLLAMA_GENERATION_MODEL` | Model used for card generation |
| `OLLAMA_EMBEDDING_MODEL` | Embedding model (default: `nomic-embed-text`) |
| `OLLAMA_READ_TIMEOUT` | HTTP read timeout in seconds (default: `300`) |

## Running

Start Ollama (if using local LLMs):
```bash
ollama serve
```

Start the Rails server:
```bash
bin/dev
```

Visit `http://localhost:3000`.

The background job queue runs automatically via Solid Queue. You can monitor jobs at `http://localhost:3000/jobs`.

## Testing

```bash
# Run all tests
bin/rails test
```

## Linting

```bash
bundle exec rubocop
```
