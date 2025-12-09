package tree_sitter_zx_test

import (
	"testing"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_zx "github.com/nurulhudaapon/zx/bindings/go"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_zx.Language())
	if language == nil {
		t.Errorf("Error loading ZX grammar")
	}
}
