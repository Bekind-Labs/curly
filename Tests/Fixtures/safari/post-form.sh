curl 'https://app.example.com/login' \
-X 'POST' \
-H 'Content-Type: application/x-www-form-urlencoded' \
-H 'Cookie: visitor=42' \
-H 'Origin: https://app.example.com' \
--data-binary 'user=ada&password=L0vel%40ce&remember=on'
