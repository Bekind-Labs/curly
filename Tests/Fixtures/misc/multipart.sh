curl 'https://api.example.com/v1/upload' \
  -F 'file=@/tmp/report.pdf' \
  -F 'title=Quarterly report' \
  -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig'
