#!/bin/bash
set -e
urls=(
  "https://iceberg.apache.org/docs/latest/spark-writes|.firecrawl/spark-writes.md"
  "https://iceberg.apache.org/docs/latest/spark-procedures|.firecrawl/spark-procedures.md"
  "https://iceberg.apache.org/docs/latest/spark-structured-streaming|.firecrawl/spark-structured-streaming.md"
)
for entry in "${urls[@]}"; do
  url="${entry%%|*}"
  out="${entry##*|}"
  until firecrawl scrape "$url" --only-main-content -o "$out"; do
    echo "retrying $url after rate limit..."
    sleep 20
  done
  echo "DONE: $out"
  sleep 15
done
echo "ALL_DONE"
