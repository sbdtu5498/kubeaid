#!/bin/sh

# I exit at the end so we print every error 
# instead of failing after it finds 1
#
# Note: Avoid using pipes (|) for loops if you need to persist state.
# In POSIX sh, each command in a pipeline executes in a subshell, 
# meaning variable assignments won't propagate back to the parent process.

EXIT_CODE=0

while read -r f; do
    # Skip empty lines if find returns nothing
    [ -z "$f" ] && continue
    if ! jsonnetfmt --test "${f}"; then
      EXIT_CODE=1
      echo "'${f}' not correctly formatted"
    fi
done <<EOF
$(find . -not -path "./build/kube-prometheus/libraries/*" -name "*.jsonnet")
EOF

if ! jsonnetfmt --test ./build/kube-prometheus/common-template.jsonnet; then
  EXIT_CODE=1
  echo "Error, bad jsonnet ./build/kube-prometheus/common-template.jsonnet"
fi

if [ $EXIT_CODE -eq 1 ]; then
  exit $EXIT_CODE
else
  echo "Success"
fi
