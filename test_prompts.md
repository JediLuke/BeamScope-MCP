# BeamScope MCP — Tool Selection Eval

Paste these scenarios one at a time into a fresh Claude Code session (in the merlinex project directory). For each one, note which tool it reaches for. The "expected" tool is listed after each scenario.

Don't share the expected answers with the LLM — just give it the scenario and see what it does.

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
"What data is the Merlinex.Core.Manager GenServer currently holding?"

**Expected**: `get_process_state` (it's asking about DATA)
**Wrong if**: `get_process_info` (that's metadata/vital signs, not state)

---

## Scenario 3: Process confusion — info vs state (reverse)
"Is Merlinex.PerfMonitor alive? What function is it currently running?"

**Expected**: `get_process_info` (asking about identity/vital signs)
**Wrong if**: `get_process_state` (that's the data, not what it's doing)

---

## Scenario 4: Finding a process first
"Which process is using the most memory in the app?"

**Expected**: `list_processes` with `sort_by: "memory"`
**Wrong if**: `get_process_info` (doesn't know which PID yet)

---

## Scenario 5: Compile after single file edit
"I just changed lib/core/manager.ex. Can you reload it?"

**Expected**: `reload_module` with the file path
**Wrong if**: `recompile` (overkill for one file) or `project_eval` with Code.compile_file

---

## Scenario 6: Compile after many changes
"I've been editing a bunch of files. Can you recompile?"

**Expected**: `recompile`
**Wrong if**: `reload_module` (only does one file) or `recompile_deps`

---

## Scenario 7: Dependency changed
"I changed some code in memelex (a path dependency). Can you recompile it?"

**Expected**: `recompile_deps` with args `["memelex", "--force"]`
**Wrong if**: `recompile` (that's project code, not deps) or `reload_module`

---

## Scenario 8: Understanding a function
"What does Enum.reduce/3 do?"

**Expected**: `get_docs` with reference "Enum.reduce/3"
**Wrong if**: `project_eval` or `xref_callers`

---

## Scenario 9: Impact analysis
"I want to refactor Merlinex.Core.Manager. What modules depend on it?"

**Expected**: `xref_callers` with reference "Merlinex.Core.Manager"
**Wrong if**: `get_docs` (that shows what it does, not who calls it)

---

## Scenario 10: Runtime vs file config
"What port is scenic_mcp actually running on?"

**Expected**: `get_app_config` with app "scenic_mcp", key "port"
**Wrong if**: Reading config files on disk (might differ from runtime)

---

## Scenario 11: System health vs config
"How much memory is the app using?"

**Expected**: `get_system_stats`
**Wrong if**: `get_app_config` (config doesn't tell you memory usage)

---

## Scenario 12: Understanding the process tree
"Show me the supervision tree for merlinex"

**Expected**: `get_supervision_tree` with app "merlinex"
**Wrong if**: `list_processes` (flat list, not hierarchical)

---

## Scenario 13: ETS discovery then inspection
"What's stored in the scenic pubsub ETS table?"

**Expected**: `list_ets_tables` first (to find the table name), then `inspect_ets_table`
**Acceptable**: `inspect_ets_table` directly if it guesses the name correctly
**Wrong if**: `project_eval` with :ets.tab2list

---

## Scenario 14: Runtime call tracing
"I want to see what happens when PerfMonitor fires. Can you trace it?"

**Expected**: `trace_calls` with module "Merlinex.PerfMonitor"
**Wrong if**: `get_process_info` (snapshot, not temporal) or `project_eval`

---

## Scenario 15: Escape hatch
"Can you check if Application.started_applications() includes :memelex?"

**Expected**: `project_eval` (no dedicated tool for this)
**Wrong if**: `get_app_config` (that's config, not started applications list)

---

## Scenario 16: Process dictionary vs state
"What are the $ancestors of the BeamScope server process?"

**Expected**: `get_process_dictionary` ($ancestors lives in the process dictionary)
**Wrong if**: `get_process_state` (state is the GenServer data, not OTP metadata) or `get_process_info`

---

## Scoring

- 16/16: Descriptions are excellent
- 13-15: Good, minor tweaks needed
- 10-12: Descriptions need work on the confused scenarios
- <10: Major rework needed
