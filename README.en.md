# MovieJournal

[简体中文](README.md) · **English** · [日本語](README.ja.md) · [한국어](README.ko.md)

Keep a record of the films and TV series you watch, with posters, ratings, and short reviews.

MovieJournal is a native macOS app built with SwiftUI and SwiftData. It supports macOS 14 and later, uses system frameworks, and stores your viewing records locally.

## What is new in 1.1.1

- Use “记录重看” (Log a rewatch) in details to save each viewing date, rating, review, and TV season. Library cards show the latest viewing information.
- The library's “…” menu offers sorting and backup/restore. JSON includes metadata, history, and cached posters. Preview additions before restoring; existing works retain their local data.
- Personal drafts are protected while adding, with a fixed save button. Search for a director's works, or search the library by title, director, creator, or cast member.
- Settings offer Off, Clear, and Regular glass plus tint strength. macOS 26 and later use native Liquid Glass; older systems use a material fallback. Reduce Transparency is respected.
- Before migrating V1 to V2, the app saves a database snapshot at Backups/BeforeV2.store inside the library directory.

## Features

- **Poster library** — Sort by date added, viewing date, or personal rating. Search titles, directors, creators, or cast members, and filter by films or TV series.
- **Online lookup** — Search TMDB and choose a work to retrieve its title, year, genres, director or creators, top five cast members, synopsis, poster, and TMDB rating.
- **Personal viewing records** — Save a viewing date, an integer rating from 1 to 10, an optional short review, and the season reached for a TV series.
- **Additional ratings** — Configure an optional OMDb API key to retrieve IMDb and Rotten Tomatoes ratings when adding a work.
- **Offline browsing and editing** — View saved metadata and successfully downloaded posters, and edit personal viewing information offline.
- **Duplicate detection and confirmed deletion** — Open the existing record when adding a duplicate. Confirm deletions and clean up posters according to the remaining records.
- **Keychain storage** — Save, validate, replace, or remove API keys in Settings.

## Getting started

1. Clone the repository and open the project in Xcode.

   ```sh
   git clone https://github.com/pengde-dede/MovieJournal.git
   cd MovieJournal
   open MovieJournal.xcodeproj
   ```

2. This version was build-verified with Xcode 27.2 and targets macOS 14 or later. Compilation requires a macOS SDK that includes Liquid Glass APIs.
3. Under **Signing & Capabilities**, enable **Automatically manage signing** and select your development team for both the app and test targets.
4. Select the **MovieJournal** scheme and **My Mac** destination, then press **⌘R**.
5. Press **⌘,** to open Settings. Enter and save a **TMDB API Key (v3)**, then click **验证** (Validate). Use the API Key (v3 auth); a long Read Access Token triggers a format warning.
6. Optionally enter an activated **OMDb API key** for additional ratings. Request keys from the official pages. [TMDB API settings](https://www.themoviedb.org/settings/api) · [OMDb API key](https://www.omdbapi.com/apikey.aspx)

## Adding a viewing record

Click **添加观影记录** (Add viewing record), enter a title, and select the correct work. Review its details, enter your viewing date and personal rating, and optionally write a short review. For TV series, enter a positive integer season number, such as `2`. You can record a season you are still watching.

Save when personal information is complete; the library can finish caching the poster afterward. Failed downloads can be retried. Additional ratings may be empty when OMDb is unconfigured, has no rating, or fails to respond. Refresh IMDb and Rotten Tomatoes ratings manually from the details page.

Saving opens the detail page, where you can edit personal information or confirm deletion. Use the main library search to find saved works and the add window to look up new ones.

## Data and current scope

| Item | Behavior |
| --- | --- |
| Work identity | Media type and TMDB ID identify each work, which can have multiple viewing entries |
| Date and rating | The date defaults to today and means the latest viewing date for TV series; an integer personal rating from 1 to 10 is required |
| Search results | Online searches show the first page of results |
| Metadata | Chinese is preferred; an empty Chinese synopsis falls back to English with a language label |
| Platform ratings | Stored as a local snapshot; OMDb ratings may be unavailable |
| Database | `Application Support/MovieJournal/MovieJournal.store` inside the app sandbox, using the V2 schema |
| Posters | Saved works use the `Posters/` subdirectory; search thumbnails use an in-memory cache |
| Offline use | Read saved metadata and cached posters, and edit or delete records |
| Sync and keys | Data is stored locally with CloudKit sync disabled; API keys use macOS Keychain with iCloud Keychain sync disabled |

The app interface currently uses Chinese. The language links at the top switch the README documentation language.

## Building and testing

Run the build and regular tests from the project root, or press **⌘U** in Xcode.

```sh
xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' build
xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' test
```

Regular tests use simulated network responses, test keys, and separate temporary databases. Optional live TMDB verification requires explicit opt-in, reads the TMDB key saved on your Mac, and makes API requests.

```sh
TEST_RUNNER_MOVIEJOURNAL_LIVE_API_TESTS=1 xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' -only-testing:MovieJournalTests/LiveAPISmokeTests test
```

Live API tests use a temporary database to verify search, metadata retrieval, poster caching, and offline editing and deletion. The development notes contain manual checks for clicks, keyboard input, window closing, and offline restarts.

## Project structure

| Path | Responsibility |
| --- | --- |
| `MovieJournal/App/` | App entry point |
| `MovieJournal/Models/` | Versioned schema, metadata, personal drafts, and migration plan |
| `MovieJournal/Persistence/` | Local container, queries, explicit saves, duplicate detection, and rollback |
| `MovieJournal/Networking/` | TMDB / OMDb requests, parsing, and error handling |
| `MovieJournal/Services/` | Keychain, key validation, metadata retrieval, poster caching, and cleanup |
| `MovieJournal/ViewModels/` | Add, edit, delete, settings, and library state |
| `MovieJournal/Views/` | SwiftUI screens and shared components |
| `MovieJournalTests/` | Swift Testing tests and optional live API verification |

## Development notes

The original README's staged acceptance procedures, historical test results, bug fixes, signing guidance, and storage notes are preserved in full. Historical results apply to the versions and dates recorded there. [Full development notes (Chinese)](docs/DEVELOPMENT.zh-CN.md)

## Data sources and acknowledgments

TMDB provides metadata and posters. OMDb provides additional IMDb and Rotten Tomatoes ratings. [TMDB API](https://developer.themoviedb.org/reference/intro/getting-started) · [OMDb API](https://www.omdbapi.com/)

This product uses the TMDB API but is not endorsed or certified by TMDB.
