The more you delegate to a coding agent, the more your time shifts from writing code to reading it. This is a note about how to read what the agent wrote. It describes the workflow used to build befold itself.

### Some problems only a reader finds

Type checks pass, the linter is quiet, the tests are green — and a human still finds things to fix. On the day this article was written, a 349-line document produced six review comments. Two of them looked like this.

- “This whole section is unnecessary — it records information the task never needs.”
- “This constraint reads like a leftover from an option we already rejected.”

Neither is about whether the text is correct. Both ask whether it belongs there at all — a question no tool answers for you. So a person has to read it, and reading needs tooling.

### 1. Narrow to what changed

An agent touches a dozen files in one go. Open the folder and most of what you see is untouched.

<figure class="article-shots"><img src="/images/usecase-review-all-files.png" alt="The sidebar lists all 11 files in the folder, with badges on the changed ones" loading="lazy" width="1512" height="949"/></figure>

Switch the sidebar to show only changed files and what is left is what you have to read. Below is the same folder, down from 11 files to 4. A marks an added file, M a modified one.

<figure class="article-shots"><img src="/images/usecase-review-changed-only.png" alt="The same folder filtered down to the four changed files, with a diff in the main pane" loading="lazy" width="1512" height="949"/></figure>

### 2. Read it as a diff

You do not need to re-read the whole file. In diff view, removed and added lines sit side by side. The comparison starts from where the branch diverged from the default branch, so committed work is included — you see everything the branch changed.

<figure class="article-shots"><img src="/images/usecase-review-diff.png" alt="A Markdown diff, with removed lines in red and added lines in green" loading="lazy" width="1512" height="949"/></figure>

### 3. Ask for a fix, keep looking

Tell the agent what you found. When it edits the file, the open window updates on its own — no reopening. Read, comment, fix, read again, all in the same window.

### Worth knowing

- Diff view needs a git repository — without one there is nothing to compare against.
- A file with no changes cannot be shown as a diff. Whether it can is not settled the moment you open it; it resolves once git status arrives.
- befold only reads. Fixing is the agent's job.
