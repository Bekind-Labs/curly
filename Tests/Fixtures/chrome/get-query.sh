curl 'https://api.example.com/v1/search?q=swift%20ui&page=2&sort=relevance' \
  -H 'accept: application/json, text/plain, */*' \
  -H 'accept-language: en-US,en;q=0.9' \
  -H 'cookie: session=abc123; theme=dark; _ga=GA1.2.9876' \
  -H 'referer: https://app.example.com/search' \
  -H 'sec-ch-ua: "Chromium";v="124", "Not:A-Brand";v="8"' \
  -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36' \
  --compressed
