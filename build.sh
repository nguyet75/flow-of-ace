#!/usr/bin/env bash
# Wraps src/app.html into a standalone, installable index.html (PWA).
set -euo pipefail
cd "$(dirname "$0")"
{
  echo '<!doctype html><html lang="en"><head><meta charset="utf-8">'
  echo '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">'
  echo '<link rel="manifest" href="manifest.webmanifest"><link rel="icon" href="icon.svg"><link rel="apple-touch-icon" href="icon.svg">'
  echo '<meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">'
  echo '<script src="config.js"></script><script src="lib/supabase.js"></script>'
  echo '<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0}[hidden]{display:none!important}</style>'
  echo '</head><body>'
  cat src/app.html
  echo '</body></html>'
} > index.html
echo "built index.html"
