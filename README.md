# bkr

[![Gem Version](https://badge.fury.io/rb/bkr.svg)](https://badge.fury.io/rb/bkr)
[![CI](https://github.com/sophiedeziel/bkr/actions/workflows/ci.yml/badge.svg)](https://github.com/sophiedeziel/bkr/actions/workflows/ci.yml)

A framework for creating **interactive EPUB 3 books**. Write chapters as HTML, run one command, and get a
valid `.epub`, with a built-in library of interactive widgets that still read well on e-readers with
scripting disabled.

## Installation

Requires Ruby 3.2+.

    $ gem install bkr

Validation uses the W3C [EPUBCheck](https://www.w3.org/publishing/epubcheck/) (bundled), which needs
**Java 11+** (`brew install openjdk` on macOS, or <https://adoptium.net>). Everything else works without Java.

## Usage

### Start a new book

    $ book new my_book
    $ cd my_book

```
my_book/
├── config/book.yml   # title, author, language, identifier, chapter order, cover...
├── content/          # chapters: HTML body fragments (well-formed XHTML)
├── assets/           # css/, js/, images/, fonts/
├── build/            # generated .epub files
└── tmp/              # bkr.log
```

### Write

Chapters in `content/` are HTML **fragments**: no `<html>`, `<head>` or `<body>`, just your content
starting with an `<h1>`. They must be well-formed XHTML (close every tag, `<br/>`, `&amp;`, numeric
entities like `&#8217;` instead of `&rsquo;`). bkr wraps each one in a full XHTML document, links the
stylesheets and scripts, and rewrites links to other chapters and assets.

Chapter order and metadata live in `config/book.yml`. Every option is documented in the generated file.

### Interactive widgets

When `bkr_assets` is on (the default), every chapter gets bkr's `bkr.css` and `bkr.js`:

```html
<div data-bkr="reveal" data-bkr-label="Show the answer">
  <p>What is 6 × 7?</p>
  <p data-bkr-hidden="">42</p>
</div>

<div data-bkr="quiz">
  <p>Which format is this book?</p>
  <ol>
    <li>PDF</li>
    <li data-bkr-correct="">EPUB 3</li>
  </ol>
  <p data-bkr-explanation="">EPUB 3 supports HTML, CSS and JavaScript.</p>
</div>

<ol data-bkr="steps">
  <li>Mix</li>
  <li>Bake</li>
  <li>Eat</li>
</ol>
```

Without JavaScript, the hidden parts are simply shown, so the content stays readable everywhere.

### Build and validate

    $ book build              # → build/my_book.epub (log in tmp/bkr.log, -v for details)
    $ book build --validate   # build, then run EPUBCheck
    $ book validate [EPUB]    # validate the project's build, or any .epub

`book build` generates the OPF manifest, spine, EPUB 3 navigation and NCX for you, and flags scripted
chapters. Chapter errors are reported with file and line number.

## Development

    $ bin/setup          # install dependencies
    $ bundle exec rake   # specs + RuboCop
    $ bin/console        # IRB with bkr loaded

Specs tagged `:java` run EPUBCheck for real and are skipped automatically when Java isn't installed.
CI runs them on GitHub Actions.

## Contributing

1. Fork it (<https://github.com/sophiedeziel/bkr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

Please follow the [code of conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE.txt)
