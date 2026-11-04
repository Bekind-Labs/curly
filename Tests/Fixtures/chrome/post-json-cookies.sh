curl 'https://api.example.com/v1/widgets?draft=true' \
  -H 'accept: */*' \
  -H 'content-type: application/json' \
  -H 'cookie: session=abc123; csrf=9f8e7d6c' \
  -H 'origin: https://app.example.com' \
  -H 'sec-fetch-mode: cors' \
  --data-raw '{"name":"Wobble","tags":["red","blue"],"count":3,"nested":{"ok":true}}' \
  --compressed
