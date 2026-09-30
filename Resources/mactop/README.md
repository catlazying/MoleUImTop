# Bundled mactop (Mole X Monitor)

Mole X Phase A uses the mactop v2 **headless JSON** binary as a long-lived collector.

## Place the binary

```bash
# From Homebrew (Apple Silicon)
cp "$(brew --prefix mactop)/bin/mactop" Resources/mactop/mactop
chmod +x Resources/mactop/mactop

# Or:
just update-mactop
```

The Xcode "Copy mactop" build phase copies this file into the app bundle at
`Contents/Resources/mactop/mactop`. If the local file is missing, the phase
falls back to `/opt/homebrew/bin/mactop` when present.

## License

mactop is MIT-licensed. See `LICENSE` in this directory (Copyright Carsen Klock).

## Notes

- Apple Silicon (arm64) only
- Do not commit the binary by default (gitignored); CI/local builds obtain it via Homebrew
- Monitor subsystem does not spawn mactop per UI refresh
