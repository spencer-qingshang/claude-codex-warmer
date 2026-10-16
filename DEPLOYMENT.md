# Codex-only deployment

This fork runs only the Codex warm-up from viseshb/claude-codex-warmer.

- GitHub Actions checks every 30 minutes, at minutes 07 and 37 (UTC).
- An active usage window is skipped. The fallback interval is 5 hours 1 minute.
- A five-hour minimum between scheduled sends prevents a broken meter from sending too often.
- Manual workflow dispatch sends a real test message, bypassing the scheduled gate.
- The model is gpt-5.6-sol with low reasoning effort and a read-only sandbox.
- Concurrent runs are serialized so they cannot rotate the same credential simultaneously.
- Authentication is restored from CODEX_AUTH_JSON and persisted back after every run, including failures.
- GH_PAT must be able to update this repository's Actions secrets.
- The daily heartbeat keeps the scheduled workflow active.
- Failed jobs use GitHub's normal Actions notifications; this fork does not post issues or comments.

The upstream README and workflow disagree about repeated Codex logins. This deployment uses a separate local login directory for the CI credential and does not overwrite the desktop auth file. Separate storage alone is not proof that the provider isolates refresh sessions. If CI reports token_revoked or refresh_token_reused, stop repeated retries and update the credential from a fresh official login.

Never commit auth.json or token values. When replacing GH_PAT, prefer a fine-grained token limited to this repository with Secrets read/write permission.
