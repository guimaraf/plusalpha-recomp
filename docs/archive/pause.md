# Architectural Planning: Pause Menu and Command List Subsystem

This document consolidates the static mapping, dependency closure, and future action plan for native recompilation of the pause menus and command lists in *Street Fighter EX Plus Alpha* (`SLUS-005.48`).

---

## 1. Subsystem Overview

The pause subsystem consists of **two main components** in the Main EXE:
1. **Main Pause Menu (`0x80172DD0..0x8017566C`)**: UI dispatcher when START is pressed during combat, displaying control, return, and reset options.
2. **Command List & Submenus (`0x80183734..0x80185860`)**: Three-dimensional graphical viewer for fighter moves and secondary settings.

---

## 2. Component 1: Main Pause Menu (`0x80172DD0..0x8017566C`)

### Metrics
- **Budget**: 10 contiguous functions.
- **Words**: 2.599 words (10.396 bytes).
- **Entry Point (Seed)**: `0x80172DD0`.
- **Master Dispatch**: Registered at index 0 of the master game-state table at `0x801AF994` (called dynamically through `jalr` at `0x80104128`).

### Block Functions
| Function | Bytes | Words | Observed Hits | Architectural Role |
|:---|:---:|:---:|:---:|:---|
| `0x80172DD0` | 3.264 | 816 | 62 | Pause menu root dispatcher; contains a 5-case jump table at `0x801AC91C`. |
| `0x80173A90` | 260 | 65 | 1 | Menu viewport and display-list setup. |
| `0x80173B94` | 684 | 171 | 1 | Text-buffer and rendering-list allocation. |
| `0x80173E40` | 600 | 150 | 2 | Menu item selection and navigation (Exit, Reset, Button Config). |
| `0x80174098` | 152 | 38 | 16 | Audio and cursor-effect triggering. |
| `0x80174130` | 1.540 | 385 | 2 | Transition and button-state processing. |
| `0x80174734` | 2.104 | 526 | 122 | Graphical renderer for onscreen boxes, fonts, and text. |
| `0x80174F6C` | 268 | 67 | 22 | Buffer cleanup and teardown when closing the UI. |
| `0x80175078` | 648 | 162 | — | Transition handler for returning to combat. |
| `0x80175300` | 876 | 219 | 1 | Match Reset confirmation ("YES / NO"). |

### Layout and Abutment
- **Lower Boundary**: Joins the compiled block `[0x801727E4..0x80172DD0]` contiguously at `0x80172DD0`.
- **Upper Boundary**: Joins the compiled block `[0x8017566C..0x801758C8]` contiguously at `0x8017566C` (promoted in batch S1-258).
- **Abutment Result**: Compilation fills 100% of the gap between the two blocks, producing a single contiguous native region `[0x801727E4..0x801758C8]`.

### Codegen & Closure Audit
- **Pending External Calls**: **EXACTLY ZERO**. All subroutines invoked through `jal` are already compiled natively.
- **Internal Jump Table (`0x801AC91C`)**: 5 cases (`0x80172E3C`, `0x801734FC`, `0x80173550`, `0x8017359C`, `0x80173638`), all strictly contained within `0x80172DD0`.
- **Closure Expansion**: **EXACTLY ZERO**.

---

## 3. Component 2: Command List & Submenus (`0x80183734..0x80185860`)

### Metrics
- **Estimated Budget**: ~30 functions.
- **Entry Point (Seed)**: `0x80183734` (index 12 of table `0x801AF994`).
- **Observed Hits in Telemetry 62**: 1.100 interpreter hits.

### Key Block Functions
- `0x80183734`: Main Command List dispatcher.
- `0x8018404C` and `0x80184138`: Input management and move-tab selection.
- `0x80185304`: String and move-sequence decoder (directional arrows and buttons).
- `0x80185618`: Text-primitive buffer formatter.
- `0x80185860` (`0x80185898`, `0x80185970`): 3D renderer for UI boxes and polygons.

### Associated GTE Pipeline
- The Command List invokes the following vector routines to render three-dimensional move icons:
  - `0x8019C224`, `0x8019C278`, `0x8019C284`, `0x8019C290`, `0x8019C3F4`
  - `0x8019DAD0`

---

## 4. Future Execution Plan

When work on this subsystem begins:
1. **Step 1: Main Pause Menu**
   - Add seed `0x80172DD0` to `entry_funcs.txt`.
   - Generate sources and validate compilation without closure expansion (+2.599 words).
   - Validate in Versus Mode by opening and closing pause without navigating to the Command List.
2. **Step 2: Command List**
   - Add seed `0x80183734` and auxiliary vector routines (`0x8019C224`, `0x8019DAD0`).
   - Validate by browsing every move page for both players.
3. **Step 3: Specialized Screens**
   - Validate in Training Mode (Dummy options) and Expert Mode (Mission Select).
