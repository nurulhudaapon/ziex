extern fn tree_sitter_mdzx() callconv(.c) *const anyopaque;
extern fn tree_sitter_mdzx_inline() callconv(.c) *const anyopaque;

pub fn language() *const anyopaque {
    return tree_sitter_mdzx();
}

pub fn inlineLanguage() *const anyopaque {
    return tree_sitter_mdzx_inline();
}
