# Read It - KOReader Plugin

> **[Read-It](https://read-it-blush.vercel.app/)** is a web application for tracking your reading habits, managing your book library, and analyzing your reading progress across multiple devices.

This KOReader plugin integrates seamlessly with the [Read-It webapp](https://read-it-blush.vercel.app/), automatically synchronizing your reading statistics and progress in real-time. Track your reading habits, view detailed analytics, and manage your library from both your e-reader and web browser.

## Features

- **Automatic Synchronization**: Syncs reading statistics automatically when saving settings or closing documents
- **Reading Sessions Tracking**: Records detailed reading sessions including page, duration, and timestamp
- **Multi-device Support**: Use a user code to sync across multiple devices, or use device-specific tracking
- **Book Metadata**: Syncs book information including title, authors, pages, and reading progress
- **Manual Sync**: Option to manually trigger synchronization at any time
- **Google Books Integration**: Link your local books with Google Books entries
- **Debug Mode**: Development mode for testing with local API endpoints

## Installation

1. Copy the `readit.koplugin` folder to your KOReader's plugins directory:

   - Copy the files `main.lua` and `_meta.lua` into a folder named `readit.koplugin` and place it in the `plugins` directory of your KOReader installation.

2. Restart KOReader

3. The plugin will appear in the "Tools" menu as "Read It"

## Configuration

### Setting Up Your User Code

1. Open any book in KOReader
2. Go to **Tools → Read It**
3. Select **"Configure user code"**
4. Enter the code generated from the Read It app
5. Click **"Save"**

> **Note**: If you don't configure a user code, the plugin will use a unique device ID as a fallback.

## Usage

### Linking a Book

1. Open a book in KOReader
2. Go to **Tools → Read It → Select book**
3. Choose the corresponding book from the list fetched from the cloud
4. The plugin will send the book's hash and metadata to link it

### Manual Synchronization

1. Open a book in KOReader
2. Go to **Tools → Read It → Sync statistics now**
3. A confirmation message will appear once sync is complete

### Automatic Synchronization

The plugin automatically syncs:

- When you close a book
- Periodically when saving settings
- Before device suspension

## Data Synchronized

The plugin syncs the following data:

- **Book Information**:
  - Title
  - Authors
  - Total pages
  - MD5 hash (for identification)
- **Reading Statistics**:
  - Total read time
  - Total pages read
  - Last opened timestamp
- **Reading Sessions**:
  - Page number
  - Session start time
  - Session duration
  - Total pages at that moment

## Menu Options

The Read It menu provides the following options:

- **Device/User ID**: Displays your current identifier (read-only)
- **Configure user code**: Set up your user code from the Read It app
- **Select book**: Link the current book with a Google Books entry
- **Sync statistics now**: Manually trigger synchronization

## Technical Details

### Dependencies

The plugin uses the following KOReader modules:

- `dispatcher`: For action registration
- `ui/widget/infomessage`: For displaying messages
- `ui/uimanager`: For UI management
- `ui/widget/menu`: For menu display
- `ui/widget/inputdialog`: For user input
- `datastorage`: For accessing KOReader's data directory
- `luasettings`: For persistent settings
- `util`: For MD5 hashing
- `json`: For API communication
- `socket.http` & `ltn12`: For HTTP requests
- `lua-ljsqlite3`: For reading statistics database

## Privacy

- The plugin only syncs data for books you explicitly link
- Your device ID is locally generated and stored
- User codes are optional and stored locally
- Only reading statistics and book metadata are transmitted

## License

This plugin is distributed under the same license as KOReader.

## Support

For issues, questions, or suggestions, please open an issue on the GitHub repository.

---

**Note**: This plugin requires an active internet connection to sync data with the Read It cloud service.
