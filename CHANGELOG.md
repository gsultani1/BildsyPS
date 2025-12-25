# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2025-12-25

### Added

#### Core Features
- Multi-provider AI chat support (Ollama, Anthropic Claude, OpenAI, LM Studio)
- Streaming responses for real-time output
- Automatic token management and conversation trimming
- Provider switching mid-conversation
- Conversation history with save/load capability

#### Intent System
- JSON-based intent routing for natural language actions
- Document creation (`create_docx`, `create_xlsx`)
- Application launching (`open_word`, `open_notepad`, `open_excel`)
- Clipboard operations (`clipboard_read`, `clipboard_write`, `clipboard_format_json`, `clipboard_case`)
- File analysis (`read_file`, `file_stats`)
- Git integration (`git_status`, `git_log`, `git_commit`, `git_push`, `git_pull`, `git_diff`)
- Outlook calendar (`calendar_today`, `calendar_week`, `calendar_create`)
- Web search (`web_search`, `wikipedia`, `fetch_url`)

#### Command Execution
- Safe command execution with whitelist validation
- User confirmation for non-read-only commands
- Rate limiting to prevent runaway execution
- Comprehensive execution logging with audit trail

#### MCP Support
- Model Context Protocol client implementation
- Connect to external MCP servers via stdio transport
- Pre-configured common servers (filesystem, memory, fetch, brave-search, github)
- Custom server registration

#### Terminal Tools Integration
- bat (syntax-highlighted file viewing)
- glow (markdown rendering)
- broot (interactive file navigation)
- fzf (fuzzy finding)
- jq/yq (JSON/YAML processing)

#### Navigation Utilities
- Directory tree visualization
- Folder size analysis
- Quick directory jumping with `z`
- Parent directory shortcuts (`..`, `...`, `....`)

### Security
- Command whitelist with safety classifications
- API keys loaded from config file (not hardcoded)
- Execution logging for audit purposes
- Rate limiting on AI command execution

### Documentation
- README with installation and usage guide
- Example configuration files
- MIT License
