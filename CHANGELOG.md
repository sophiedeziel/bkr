# Changelog

## 0.0.2 (unreleased)

First release that actually turns a project into an EPUB 🎉

### Added
- `book new NAME` now generates a complete starter project: `config/book.yml`, sample chapters, assets folders, `.gitignore` and README (#2).
- `config/book.yml` for metadata, chapter order, cover, stylesheets and scripts (#7).
- `book build` packages the project into `build/<name>.epub`, generating the OPF manifest, spine and EPUB 3 navigation automatically (#3, #5).
- `book validate [EPUB]` and `book build --validate` run the W3C EPUBCheck 5.3 (requires Java) (#4).
- Bundled `bkr.css` and `bkr.js` with progressive-enhancement interactive widgets (#6).
- Build log in `tmp/bkr.log` and `--verbose` flag (#8).
- `book version` / `book --version`.

### Changed
- Requires Ruby 3.2+. Thor 1.x, Rake 13, RSpec 3.13.
- Replaced the unmaintained `epub_validator` gem with `epubcheck-ruby`.
- EPUB generation uses `gepub`.
- CI moved from Travis CI to GitHub Actions; Guard removed; RuboCop added.

## 0.0.1 (2015-05-27)

- `book new NAME` creates an empty project skeleton.
