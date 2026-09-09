<p align="center">
  <img src="AMT/Assets.xcassets/logo_black.imageset/Lawtionary%20Logo%20Black.png" alt="Lawtionary logo" width="112">
</p>

<h1 align="center">Lawtionary (AMT)</h1>

<p align="center">
  A macOS application for reviewing document drafts and looking up Indonesian legal terms.
</p>

Lawtionary has two complementary MVPs:

- <strong>Document</strong> for importing, reading, editing, reviewing suggestions, and exporting drafts.
- <strong>Dictionary</strong> for looking up legal terms, definitions, and available source context.

> [!WARNING]
> Lawtionary is a work-assistance tool and is still an MVP. It is not legal advice, it does not certify that a document is legally correct, and it never changes document content without the user's decision. All results must be reviewed by a qualified professional.

## Contents

- [The two MVPs](#the-two-mvps)
- [MVP 1 — Document](#mvp-1--document)
- [MVP 2 — Dictionary](#mvp-2--dictionary)
- [Local storage and safe use](#local-storage-and-safe-use)
- [Getting started](#getting-started)
- [For developers](#for-developers)
- [Further documentation](#further-documentation)

## The two MVPs

| MVP | Simple purpose | What the user sees |
| --- | --- | --- |
| Document | Open a draft in one place so it can be edited and reviewed. | A working document, marked passages to inspect, accept or dismiss actions, and Word export. |
| Dictionary | Find the meaning of a legal term from the dictionary bundled with the app. | A primary definition, available source or regulation context, and related terms. |

The two features are intentionally separate. Dictionary focuses on source-backed terminology information, while Document focuses on the user's draft and human review decisions.

## MVP 1 — Document

Document is a workspace for drafts that users already have. It can import <code>.docx</code>, <code>.doc</code>, <code>.rtf</code>, <code>.md</code>, <code>.markdown</code>, and <code>.txt</code> files from Finder.

AMT creates a local working copy, checks whether the same file or content has already been imported, and opens the document in the editor. Users can change text and basic formatting, read marked suggestions, inspect available reasons or references, and decide what to do with each result.

### Document workflow

~~~mermaid
flowchart TD
    A["Choose the Document tab"] --> B["Import a file from Finder"]
    B --> C{"Can the file be read?"}
    C -- "No" --> X["Show an import error"]
    C -- "Yes" --> D{"Does the same file or content already exist?"}
    D -- "Yes" --> E["Offer to open the existing document"]
    D -- "No" --> F["Save a local working copy"]
    F --> G["Open the document in the editor"]
    G --> H["AMT marks passages that may need review"]
    H --> I["Read each suggestion and its available evidence"]
    I --> J{"Accept the change?"}
    J -- "Yes" --> K["Apply the change in the editor"]
    J -- "No or not sure" --> L["Dismiss it or mark it as reviewed"]
    K --> M["Save the change locally"]
    L --> M
    M --> N["Export the result as a Word file (.docx)"]
~~~

Keep these points in mind when using Document:

- A suggestion is a starting point for review, not an instruction to change the draft.
- Users can accept, dismiss, or mark a finding as reviewed.
- Editing the document can make an earlier review stale; run the review again before relying on it.
- The app is not intended to create contracts from scratch, replace large sections automatically, or decide the legal effect of a clause.

## MVP 2 — Dictionary

Dictionary lets users search for a legal term or enter a short description to find relevant terminology. Results come from a versioned dictionary bundle shipped with the app, not from free-form chatbot answers.

For short and clear terms, AMT only shows results with literal dictionary evidence. If there is no sufficiently good match, the app reports that the term was not found instead of showing a convincing but unrelated answer. Longer descriptions can use semantic search as an additional retrieval path.

### Dictionary workflow

~~~mermaid
flowchart TD
    A["Choose the Dictionary tab"] --> B["Enter a term or short description"]
    B --> C["Search the Lawtionary dictionary"]
    C --> D{"Is there a sufficiently supported result?"}
    D -- "No" --> E["Show that the term was not found"]
    E --> F["Check the spelling or try another term"]
    D -- "Yes" --> G["Show the relevant results"]
    G --> H["Choose a term to read"]
    H --> I["Read the primary definition and context"]
    I --> J["Open the legal basis, source, or related terms when available"]
    J --> K["Use it as input for professional review"]
~~~

The detail page may show a primary definition, contextual alternatives, regulation status or history, legal references, mapped evidence text, and related terms. Not every entry has every type of information.

> [!NOTE]
> Short-term searches use the local lexical index. Searches based on longer descriptions may load an additional retrieval component the first time they are used.

## Local storage and safe use

- The Document workspace is stored locally at <code>~/Documents/AMT_Documents</code>.
- The original file at its initial location is not overwritten. AMT keeps a working copy so the document can be reopened from the workspace.
- Deleting a document from AMT removes only its workspace record and AMT's preserved copy; the original file remains at its initial location.
- Some model-assisted review features may download model components on first use. A downloaded model is not evidence that a review result is legally correct.
- A missing Dictionary result does not mean that a term never exists in law. It means that the active dictionary did not find a sufficiently precise result.

## Getting started

### Requirements

- macOS 26.5 or later.
- Xcode 26.6, or a compatible Xcode 26 toolchain.
- Apple Silicon is recommended for model-assisted review.

### Open the project

~~~sh
git clone https://github.com/MorpKnight/AMT.git
cd AMT
open AMT.xcodeproj
~~~

In Xcode, select the <code>AMT</code> scheme, choose a macOS destination, and run the app with <code>⌘R</code>.

### Try both MVPs

1. In the Document tab, choose the import card and select a supported file.
2. Open the imported document, edit it if needed, and review suggestions one by one.
3. Export the working version as <code>.docx</code> when the review is complete.
4. In the Dictionary tab, search for a term such as <em>Data Pribadi</em>, or enter a description of the term you need.
5. Read the available definition and sources before using them in professional work.

## For developers

### Project map

~~~text
AMT/
├── Dashboard/                 # Import, local storage, and document list
├── Suggestion/                # Rich-text editor and review UI
├── Dictionary/                # Legal-term search and detail views
├── Features/AIConnector/      # Bounded, reviewable document analysis
├── Shared/LegalKnowledge/     # Corpus loading and semantic retrieval
├── Resources/legal_corpus/    # Active dictionary bundle and version manifest
└── AMTApp.swift               # Application entry point
AMTTests/                      # Deterministic and integration tests
Scripts/export_amt_legal_corpus.py
~~~

The active corpus is recorded in the [dictionary manifest](AMT/Resources/legal_corpus/manifest.json). The manifest stores the corpus version, data counts, retrieval settings, and file hashes for consistency checks.

### Build and test

Use a DerivedData directory outside the repository so build artifacts do not enter the working tree.

~~~sh
validation_dir="$(mktemp -d /tmp/amt-build-validation.XXXXXX)"
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$validation_dir" \
  build \
  CODE_SIGNING_ALLOWED=NO
~~~

~~~sh
test_dir="$(mktemp -d /tmp/amt-test-validation.XXXXXX)"
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$test_dir" \
  test \
  CODE_SIGNING_ALLOWED=NO
~~~

~~~sh
git diff --check
~~~

The regular test suite is designed to run without downloading Qwen. Model benchmarks are opt-in because they download a model and provide experimental evidence, not proof of legal correctness.

## Further documentation

- [Document product audit](docs/document-product-audit-2026-09-08.md) — current behavior, known limitations, and validation boundaries.
- [Document future development](docs/document-future-development.md) — a roadmap; the capabilities described there are not automatically available in the current app.
- [Repository instructions](AGENTS.md) — architecture, change boundaries, and validation commands.
