curl --url 'http://localhost:8080/health' -I -L -k --compressed -A 'curly/1.0' -e 'https://example.com' --max-time 10 --retry 3
