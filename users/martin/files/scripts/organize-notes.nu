#!/usr/bin/env nix-shell
#!nix-shell -i nu -p nushell

let vault_path = ($env.HOME | path join "Documents/Notes")

if not ($vault_path | path exists) {
    print $"📂 Creating Obsidian Vault directory at ($vault_path)..."
    mkdir $vault_path
}

print $"📂 Organizing Vault: ($vault_path)"

# 1. Create PARA Structure
let dirs = ["Inbox", "Areas", "Resources", "Archives", "Attachments"]
for d in $dirs {
    let p = ($vault_path | path join $d)
    if not ($p | path exists) {
        mkdir $p
    }
}

# 2. Move root files to appropriate folders
def move_if_exists [src: string, target: string] {
    if $src == $target {
        return
    }
    let vault = ($env.HOME | path join "Documents/Notes")
    let source = ($vault | path join $src)
    let dest = ($vault | path join $target)
    if ($source | path exists) {
        print $"   Moving ($src) -> ($target)/"
        mv $source $dest
    }
}

# --- Move Directories ---
move_if_exists "Finance" "Areas"
move_if_exists "Taekwondo" "Areas"
move_if_exists "Learning" "Resources"
move_if_exists "Chrome Os Flex" "Resources"
move_if_exists "Projects" "Projects"

# --- Move Files ---
move_if_exists "temp.md" "Inbox"
move_if_exists "Eltern Sport.md" "Areas"

# --- Move Attachments (Images) ---
try {
    ls ($vault_path | path join "*.png") | each { |it| mv $it.name ($vault_path | path join "Attachments") }
}
try {
    ls ($vault_path | path join "*.jpg") | each { |it| mv $it.name ($vault_path | path join "Attachments") }
}

print "✅ Organization complete!"

# 3. Distill (CODE workflow's "Distill" step): surface Areas/Resources notes
# that are stale and never summarized, so progressive summarization actually
# happens instead of Resources becoming a pile of raw, unrevisited dumps.
# This only flags candidates — writing the actual summary is a human
# judgment call, not something to automate.
let distill_days = 30
let now = (date now)

print ""
print $"📖 Distill: notes untouched ($distill_days)+ days with no [!summary] callout yet"

let distill_candidates = (
    ["Areas", "Resources"]
    | each { |folder|
        let dir = ($vault_path | path join $folder)
        if ($dir | path exists) {
            glob ($dir | path join "**/*.md")
        } else {
            []
        }
    }
    | flatten
    | each { |f| { path: $f, meta: (ls $f | first) } }
    | where { |row|
        let content = (open --raw $row.path)
        let has_summary = ($content | str contains "[!summary]")
        let age_days = (($now - $row.meta.modified) / 1day)
        (not $has_summary) and ($age_days >= $distill_days)
    }
)

if ($distill_candidates | is-empty) {
    print "   ✅ Nothing due — every Areas/Resources note is either recent or already distilled."
} else {
    for c in $distill_candidates {
        print $"   - ($c.path | path relative-to $vault_path)"
    }
    print $"   ($distill_candidates | length) note\(s\) due for distillation."
    print "   Add a `> [!summary]` callout with the key takeaway, or move to Archives if stale."
}

# 4. Regenerate the vault's AGENTS.md: a single orientation file sitting
# between the raw notes and any LLM touching the vault (Claude Code
# sessions, persona-runtime containers), mirroring the CLAUDE.md/AGENTS.md
# pattern every code repo in this fleet already uses. Generated fresh every
# run so it can't go stale like a hand-written index would.
print ""
print "🧭 Regenerating AGENTS.md..."

let known_para = ["Inbox", "Areas", "Resources", "Archives", "Projects", "Attachments", "System"]
let top_dirs = (ls $vault_path | where type == dir | get name | each { |p| $p | path basename } | sort)

mut structure_lines = []
mut leftover_lines = []
for d in $top_dirs {
    let dir = ($vault_path | path join $d)
    let count = (glob ($dir | path join "**/*.md") | length)
    if $d in $known_para {
        $structure_lines = ($structure_lines | append $"- ($d): ($count) notes")
    } else {
        $leftover_lines = ($leftover_lines | append $"- ($d): ($count) notes")
    }
}

let kdir = ($vault_path | path join "System/Knowledge")
mut knowledge_lines = []
if ($kdir | path exists) {
    for entry in (ls $kdir) {
        let target = (^readlink -f $entry.name)
        $knowledge_lines = ($knowledge_lines | append $"- ($entry.name | path basename) -> ($target)")
    }
}
if ($knowledge_lines | is-empty) {
    $knowledge_lines = ["(none linked yet — run `notes::link-docs`)"]
}

mut agents_distill_lines = []
for c in $distill_candidates {
    $agents_distill_lines = ($agents_distill_lines | append $"- ($c.path | path relative-to $vault_path)")
}
if ($agents_distill_lines | is-empty) {
    $agents_distill_lines = ["(none due)"]
}

let recent = (
    glob ($vault_path | path join "**/*.md")
    | where { |f| not ($f | str starts-with ($vault_path | path join "System")) }
    | each { |f| { path: $f, meta: (ls $f | first) } }
    | where { |row| (($now - $row.meta.modified) / 1day) <= 7 }
    | sort-by { |row| $row.meta.modified } --reverse
)
mut recent_lines = []
for r in $recent {
    $recent_lines = ($recent_lines | append $"- ($r.path | path relative-to $vault_path)")
}
if ($recent_lines | is-empty) {
    $recent_lines = ["(nothing touched in the last 7 days)"]
}

let leftover_section = if ($leftover_lines | is-empty) {
    []
} else {
    ["", "Non-PARA leftovers (not managed by `organize`, needs manual triage):"] ++ $leftover_lines
}

let agents_lines = (
    [
        "# Notes vault — AGENTS.md"
        ""
        "Auto-generated by `just os notes::organize` (nix-config/users/martin/files/scripts/organize-notes.nu)."
        "Do not hand-edit — regenerated on every organize run."
        ""
        "## Structure (PARA)"
        ""
    ]
    ++ $structure_lines
    ++ $leftover_section
    ++ [
        ""
        "## System/Knowledge (symlinked repo `.agent/` directories)"
        ""
    ]
    ++ $knowledge_lines
    ++ [
        ""
        $"## Distillation due \(($distill_days)+ days stale, no [!summary] callout\)"
        ""
    ]
    ++ $agents_distill_lines
    ++ [
        ""
        "## Recently touched (last 7 days)"
        ""
    ]
    ++ $recent_lines
    ++ [""]
)

let agents_path = ($vault_path | path join "AGENTS.md")
$agents_lines | str join "\n" | save -f $agents_path
print $"   ✅ Wrote ($agents_path)"
