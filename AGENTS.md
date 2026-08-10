# Repository Guidelines

## Project Structure & Module Organization

This Rails 8.1 app converts rulebook PDFs into searchable rules and Anki flashcards. Standard Rails code lives under `app/`; `app/services/` contains the PDF, LLM, indexing, search, and export pipeline. Hotwire views are in `app/views/`, while Stimulus controllers and JavaScript modules are in `app/javascript/`. Experimental extraction stages live in `app/microservice/`. Migrations and the main, queue, cache, and cable schemas are under `db/`. Put tests in the matching subtree under `test/` and architectural notes in `docs/`.

## Build, Test, and Development Commands

- `mise install && bundle install` installs Ruby 4.0.1 and gem dependencies.
- `bin/setup` installs dependencies, prepares the database, and starts development; add `--skip-server` for setup only.
- `bin/dev` starts the Rails app at `http://localhost:3000`. Start `ollama serve` separately when using local models.
- `bin/rails db:prepare` creates or migrates the SQLite databases.
- `bin/rails test` runs the Minitest suite; use `bin/rails test test/models/example_test.rb:12` for a focused test.
- `bin/rubocop` checks Rails Omakase style.
- `bin/ci` runs setup, lint, dependency/security audits, Brakeman, tests, and seed validation.

## Coding Style & Naming Conventions

Follow Rails conventions and the repository's `.rubocop.yml`. Use two-space indentation in Ruby, snake_case for files and methods, CamelCase for classes/modules, and plural resource names for controllers and tables. Name services by responsibility, such as `RulebookNormalizer`, and jobs with a `Job` suffix. Keep Stimulus files named `*_controller.js`. Prefer small pipeline stages over adding unrelated behavior to controllers or models.

## Testing Guidelines

Tests use Rails Minitest, with Capybara and Selenium available for system tests. Mirror application paths (`app/services/rule_searcher.rb` → `test/services/rule_searcher_test.rb`) and name test classes `*Test`. Cover success, failure, and persistence behavior, especially around LLM responses and jobs. Stub external model calls so tests remain deterministic. There is no documented coverage threshold; new behavior should include regression tests.

## Commit & Pull Request Guidelines

Recent history uses short, sentence-style subjects (for example, `Bug cleanup`). Prefer a clearer imperative subject such as `Handle malformed rule extraction`, keeping each commit narrowly scoped. Pull requests should explain the user-visible change, note schema or environment changes, link the relevant issue, and list verification commands. Include screenshots for view changes and call out any required Ollama model or API key; never commit `.env` files, credentials, uploaded PDFs, or generated exports.
