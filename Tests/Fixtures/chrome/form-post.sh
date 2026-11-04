curl 'https://app.example.com/settings' \
  -H 'content-type: application/x-www-form-urlencoded' \
  -H 'cookie: session=abc123' \
  --data-raw 'theme=dark&notify=weekly&name=Ada%20Lovelace' \
  --compressed
