# BeamScope MCP — Tool Selection Eval

These scenarios test whether an LLM selects the correct BeamScope tool based on the tool descriptions alone. Paste them one at a time into a fresh AI coding session. Don't share the expected answers — just give it the scenario and see which tool it reaches for.

Replace `MyApp` with your actual application/module names when testing.

---

## Scenario 1: Basic debugging
"The app seems slow. Can you check if there's anything wrong?"

**Expected**: MUST call `get_logs` (check for errors/warnings). May also call `get_system_stats` and `list_processes`.
**Wrong if**: reaches for `project_eval`
**Critical failure if**: claims "no errors in logs" without actually calling `get_logs`

### Scenario 1b: Explicit error check
"Are there any errors in the app right now?"

**Expected**: `get_logs` with level "error" or grep "error"
**Wrong if**: `get_system_stats` (stats don't show errors) or just reading log files on disk

### Scenario 1c: Something crashed
"I think something crashed. Can you check?"

**Expected**: `get_logs` first (look for crash/error messages), then possibly `get_supervision_tree` or `list_processes`
**Wrong if**: skips logs entirely

---

## Scenario 2: Process confusion — info vs state
"What data is the MyApp.Server GenServer currently holding?"

**Expected**: `get_process_state` (it's asking about DATA)
**Wrong if**: `get_process_info` (that's metadata/vital signs, not state)

---

## Scenario 3: Process confusion — info vs state (reverse)
"Is MyApp.Worker alive? What function is it currently running?"

**Expected**: `get_process_info` (asking about identity/vital signs)
**Wrong if**: `get_process_state` (that's the data, not what it's doing)

---

## Scenario 4: Finding a process first
"Which process is using the most memory in the app?"

**Expected**: `list_processes` with `sort_by: "memory"`
**Wrong if**: `get_process_info` (doesn't know which PID yet)

---

## Scenario 5: Compile after single file edit
"I just changed lib/my_app/worker.ex. Can you reload it?"

**Expected**: `reload_module` with the file path
**Wrong if**: `recompile` (overkill for one file) or `project_eval` with Code.compile_file

---

## Scenario 6: Compile after many changes
"I've been editing a bunch of files. Can you recompile?"

**Expected**: `recompile`
**Wrong if**: `reload_module` (only does one file) or `recompile_deps`

---

## Scenario 7: Dependency changed
"I changed some code in my_lib (a path dependency). Can you recompile it?"

**Expected**: `recompile_deps` with args `["my_lib", "--force"]`
**Wrong if**: `recompile` (that's project code, not deps) or `reload_module`

---

## Scenario 8: Understanding a function
"What does Enum.reduce/3 do?"

**Expected**: `get_docs` with reference "Enum.reduce/3"
**Wrong if**: `project_eval` or `xref_callers`

---

## Scenario 9: Impact analysis
"I want to refactor MyApp.Server. What modules depend on it?"

**Expected**: `xref_callers` with reference "MyApp.Server"
**Wrong if**: `get_docs` (that shows what it does, not who calls it)

---

## Scenario 10: Runtime vs file config
"What port is my_app actually running on?"

**Expected**: `get_app_config` with app name and key "port"
**Wrong if**: Reading config files on disk (might differ from runtime)

---

## Scenario 11: System health vs config
"How much memory is the app using?"

**Expected**: `get_system_stats`
**Wrong if**: `get_app_config` (config doesn't tell you memory usage)

---

## Scenario 12: Understanding the process tree
"Show me the supervision tree for my_app"

**Expected**: `get_supervision_tree` with app name
**Wrong if**: `list_processes` (flat list, not hierarchical)

---

## Scenario 13: ETS discovery then inspection
"What's stored in the MyApp.Cache ETS table?"

**Expected**: `list_ets_tables` first (to find the table name), then `inspect_ets_table`
**Acceptable**: `inspect_ets_table` directly if it guesses the name correctly
**Wrong if**: `project_eval` with :ets.tab2list

---

## Scenario 14: Runtime call tracing
"I want to see what happens when MyApp.Worker handles a message. Can you trace it?"

**Expected**: `trace_calls` with the module name
**Wrong if**: `get_process_info` (snapshot, not temporal) or `project_eval`

---

## Scenario 15: Escape hatch
"Can you check if Application.started_applications() includes :my_lib?"

**Expected**: `project_eval` (no dedicated tool for this)
**Wrong if**: `get_app_config` (that's config, not started applications list)

---

## Scenario 16: Process dictionary vs state
"What are the $ancestors of the BeamScope server process?"

**Expected**: `get_process_dictionary` ($ancestors lives in the process dictionary)
**Wrong if**: `get_process_state` (state is the GenServer data, not OTP metadata) or `get_process_info`

---

## Results (2026-03-24, Claude Opus 4.6)

Tested in a fresh Claude Code session with no prior context about which tool does what — only the tool descriptions were available.

| # | Scenario | Expected Tool | Actual Tool | Result |
|---|----------|--------------|-------------|--------|
| 1 | Vague debugging | get_logs | get_system_stats + list_processes | **partial** — didn't check logs unprompted |
| 1b | Explicit error check | get_logs | get_logs (level: "error") | **pass** |
| 1c | Something crashed | get_logs | get_logs (grep: crash patterns) | **pass** |
| 2 | Process data | get_process_state | get_process_state | **pass** |
| 3 | Process identity | get_process_info | get_process_info | **pass** |
| 4 | Top memory process | list_processes | list_processes (sort: memory) | **pass** |
| 5 | Single file reload | reload_module | reload_module | **pass** |
| 6 | Multi-file recompile | recompile | recompile | **pass** |
| 7 | Dependency recompile | recompile_deps | recompile_deps | **pass** |
| 8 | Understanding a function | get_docs | get_docs | **pass** |
| 9 | Impact analysis | xref_callers | xref_callers | **pass** |
| 10 | Runtime config | get_app_config | get_app_config | **pass** |
| 11 | Memory usage | get_system_stats | get_system_stats | **pass** |
| 12 | Supervision tree | get_supervision_tree | get_supervision_tree | **pass** |
| 13 | ETS inspection | list_ets_tables → inspect_ets_table | list_ets_tables → inspect_ets_table | **pass** |
| 14 | Tracing | trace_calls | trace_calls → Read file | **pass** |
| 15 | Escape hatch | project_eval | project_eval | **pass** |
| 16 | Process dictionary | get_process_dictionary | get_process_dictionary | **pass** |

**Score: 17/18 pass, 1 partial**

### Notes

- The only partial failure is scenario 1 (vague "something seems wrong") where the LLM skips logs and goes straight to system stats. When prompted specifically about errors or crashes (1b, 1c), it nails get_logs every time. This appears to be a model reasoning pattern rather than a description issue.
- The `Elixir.` prefix auto-resolution means process names like "MyApp.Server" and ETS table names like "MyApp.Cache" resolve correctly without needing the "Elixir." prefix.
- The compile triplet (5/6/7) showed perfect discrimination — the WHEN TO USE / NOT FOR descriptions work well for this category.
- The process triplet (2/3/16) also showed perfect discrimination — "DATA vs vital signs vs hidden metadata" framing in descriptions is effective.

## Scoring Guide

- 16+/18: Descriptions are excellent
- 13-15: Good, minor tweaks needed
- 10-12: Descriptions need work on the confused scenarios
- <10: Major rework needed
