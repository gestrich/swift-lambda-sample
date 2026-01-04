# Make Claude Chain Test Project

Create a simple test project in the `claude-chain/` directory for testing Claude chain workflows.

## Instructions

1. **Delete existing test project(s)** in `claude-chain/`:
   ```bash
   rm -rf claude-chain/*
   ```

2. **Create a new project directory** with a simple, descriptive name:
   ```bash
   mkdir -p claude-chain/<project-name>
   ```
   Examples: `print-hello`, `print-goodbye`, `count-numbers`

3. **Create `spec.md`** with this structure:
   ```markdown
   # <Project Title>

   <Brief description of what the tasks do.>

   ## Instructions

   <Simple instructions explaining how to complete each task.>

   **Example:**
   ```bash
   <example command>
   ```

   ## Tasks

   - [ ] `<task 1>`
   - [ ] `<task 2>`
   - [ ] `<task 3>`
   - [ ] `<task 4>`
   - [ ] `<task 5>`
   ```

4. **Commit and push**:
   ```bash
   git add -A
   git commit -m "Replace <old-project> with <new-project> test project"
   git push origin dev
   ```

## Example spec.md

```markdown
# Print Hello

Print different versions of "Hello World!" with varying exclamation marks.

## Instructions

For each task, use `echo` to print the exact string shown. Just print it, no other action is needed.

**Example:**
```bash
echo "Hello World!"
```

## Tasks

- [ ] `echo "Hello World!"`
- [ ] `echo "Hello World!!"`
- [ ] `echo "Hello World!!!"`
- [ ] `echo "Hello World!!!!"`
- [ ] `echo "Hello World!!!!!"`
```

## Key Points

- Keep tasks trivially simple (echo statements, basic commands)
- Use 5 tasks as a standard count
- Tasks should be nearly identical with small variations
- No external dependencies or complex setup required
