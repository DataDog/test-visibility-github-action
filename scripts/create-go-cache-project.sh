#!/usr/bin/env bash
# Writes the Go project of the CI's cache jobs into go-cache: a module named
# MODULE_PATH whose test needs github.com/google/go-cmp.
set -euo pipefail

mkdir -p go-cache
cat > go-cache/go.mod <<EOF
module $MODULE_PATH

go 1.22

require github.com/google/go-cmp v0.7.0
EOF
cat > go-cache/go.sum <<'EOF'
github.com/google/go-cmp v0.7.0 h1:wk8382ETsv4JYUZwIsn6YpYiWiBsYLSJiTsyBybVuN8=
github.com/google/go-cmp v0.7.0/go.mod h1:pXiqmnSA92OHEEa9HXL2W4E7lf9JzCmGVUdgjX3N/iU=
EOF
cat > go-cache/cache_test.go <<'EOF'
package cache

import (
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestCache(t *testing.T) {
	if diff := cmp.Diff(1, 1); diff != "" {
		t.Fatal(diff)
	}
}
EOF
