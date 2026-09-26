#!/bin/zsh
pending_a=""
while IFS= read -r line; do
  id="$(print -r -- "$line" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
  method="$(print -r -- "$line" | sed -n 's/.*"method":"\([^"]*\)".*/\1/p')"
  case "$method" in
    initialize)
      print -r -- "{\"jsonrpc\":\"2.0\",\"id\":\"$id\",\"result\":{}}"
      ;;
    requestA)
      pending_a="$id"
      ;;
    requestB)
      print -r -- '{"jsonrpc":"2.0","method":"progress","params":{"step":"between"}}'
      print -r -- "{\"jsonrpc\":\"2.0\",\"id\":\"$id\",\"result\":{\"value\":\"B\"}}"
      print -r -- "{\"jsonrpc\":\"2.0\",\"id\":\"$pending_a\",\"result\":{\"value\":\"A\"}}"
      ;;
  esac
done
