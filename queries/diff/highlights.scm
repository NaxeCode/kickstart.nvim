; tree-sitter-diff's current parser exposes additions, deletions, and hunk
; locations but the registry highlight query still names nodes removed from
; the grammar. Keep the stable core captures until that query catches up.

(addition) @diff.plus

(deletion) @diff.minus

(location) @attribute
