# 📋 Claude New Chat Prompt Template for Different Scenarios

## When No New Information:

Continue with WSL plugin development per CLAUDE.md priorities.

## When You Have New Test Results:

Continue with WSL plugin development. Test results since last update:
- [specific error/success details]
- [build output snippets]
- [any attempted solutions]

## When You Want to Change Priorities:

Continue with WSL plugin development. Priority change:
- Move task X to high priority because [reason]
- Add new task: [description]

## When You Have External Information:

Continue with WSL plugin development. New information:
- Found relevant Stack Overflow post: [link/details]
- Discovered compiler flag: [flag and purpose]
- Microsoft docs suggest: [approach]

# 🔄 Why This Works Best

1. Automatic Context Loading: I'll read CLAUDE.md immediately and understand current state
2. Efficient Communication: No need to repeat known information
3. Delta Updates: You only provide what's changed since last CLAUDE.md update
4. Task Continuity: I'll pick up from the current task queue priorities

# 📝 Information Flow Pattern

Your Starting Prompt → I Read CLAUDE.md → I Update CLAUDE.md → Work on Tasks → Update CLAUDE.md Again

# 🎯 Best Practices

- Keep it short: The context is already in CLAUDE.md
- Focus on deltas: Only mention new information or priority changes
- Be specific: "Build failed with error X" vs "still not working"
- Reference tasks: "Tried task #1, got result Y, ready for task #2"
