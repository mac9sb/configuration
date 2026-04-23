#!/usr/bin/env bash

set -euo pipefail

ROOT="${1:-$HOME/Developer/study/physics}"
CREATED_AT="$(date +"%Y-%m-%d")"
COURSE_URL="https://www.open.ac.uk/courses/physics/degrees/bsc-physics-r51/"
COURSE_TITLE="BSc (Honours) Physics"
COURSE_CODE="R51"

mkdir -p "$ROOT"
touch "$ROOT/.typst-root"

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

write_file() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  cat >"$path"
}

write_file "$ROOT/.gitignore" <<'EOF'
.DS_Store
build/
out/
*.pdf
*.png
*.svg
EOF

write_file "$ROOT/README.md" <<EOF
# Open University Physics Study Workspace

This workspace was generated on ${CREATED_AT} for the Open University ${COURSE_TITLE} (${COURSE_CODE}).

Official qualification page:
- ${COURSE_URL}

## Layout

- \`templates/\`: shared Typst template files
- \`course/\`: qualification-level planning, admin, and revision material
- \`modules/\`: one directory per module with prefilled note-taking documents
- \`archive/\`: old exports, retired notes, and completed material

## Working Pattern

1. Open a module directory.
2. Edit \`notes.typ\` during study.
3. Put assignment prep in \`assignments/\`.
4. Put tutorial and exam prep in \`revision/\`.
5. Compile with \`typst compile notes.typ\` or rely on Tinymist export-on-save in Neovim.

## Module Coverage

This scaffold includes:
- Stage 1 standard, basic maths, and advanced starts
- Stage 2 core modules
- Stage 3 core modules and option modules
- The final project module \`SXP390\`
- Qualification-wide admin, planning, and capstone/project material
EOF

write_file "$ROOT/templates/ou-physics-template.typ" <<'EOF'
#let accent = rgb("#2A5B8A")
#let ink = rgb("#1C2430")
#let muted = rgb("#6B7683")

#set page(
  paper: "a4",
  margin: (x: 16mm, y: 18mm),
)

#set text(
  font: ("New Computer Modern", "SF Pro Text", "Helvetica Neue"),
  size: 10.5pt,
  fill: ink,
)

#set par(justify: true, leading: 0.7em)
#set heading(numbering: "1.")
#set enum(numbering: "1.")
#set math.equation(numbering: "(1)")

#let meta-card(label, value) = block(
  inset: 8pt,
  radius: 6pt,
  fill: luma(246),
  stroke: (paint: luma(220), thickness: 0.6pt),
)[
  *#label*\
  #set text(fill: muted)
  #value
]

#let banner(title, subtitle: none) = block(
  inset: 14pt,
  radius: 10pt,
  fill: rgb("#EEF4FA"),
  stroke: (paint: accent, thickness: 1pt),
)[
  #set text(size: 18pt, weight: "bold", fill: accent)
  #title
  #if subtitle != none [
    #set text(size: 10pt, fill: muted)
    #subtitle
  ]
]

#let course-note(
  title: "",
  code: "",
  stage: "",
  credits: "",
  start_month: "",
  route: "",
  source_url: "",
  generated: "",
  body: none,
) = {
  banner(
    title,
    subtitle: "Open University BSc (Hons) Physics (R51)",
  )

  v(10pt)

  grid(
    columns: (1fr, 1fr, 1fr),
    gutter: 8pt,
    meta-card("Module code", code),
    meta-card("Stage / route", if route == "" { stage } else { stage + " / " + route }),
    meta-card("Credits / start", credits + " credits / " + start_month),
    meta-card("Source", source_url),
    meta-card("Generated", generated),
    meta-card("Status", "Active study notes"),
  )

  v(14pt)
  if body != none {
    body
  }
}
EOF

write_file "$ROOT/course/qualification-overview.typ" <<EOF
#import "../templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "Qualification Overview",
  code: "${COURSE_CODE}",
  stage: "Whole qualification",
  credits: "360",
  start_month: "October / February depending on route",
  route: "All starts",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Qualification Summary

This workspace tracks the Open University ${COURSE_TITLE} (${COURSE_CODE}).

== Structure

- Stage 1: standard, basic maths, and advanced start pathways
- Stage 2: core physics, mathematical methods, and remote experiments
- Stage 3: electromagnetism, quantum physics, one option module, and the final project module

== Personal Objectives

- Degree aim:
- Current stage:
- Planned study pace:
- Expected completion date:

== Standing References

- Official qualification page: ${COURSE_URL}
- Tutor details:
- StudentHome links:
- Library links:
EOF

write_file "$ROOT/course/study-plan.typ" <<EOF
#import "../templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "Study Plan",
  code: "${COURSE_CODE}",
  stage: "Whole qualification",
  credits: "360",
  start_month: "Rolling plan",
  route: "Personal timetable",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Year-by-Year Plan

- Year 1:
- Year 2:
- Year 3:
- Year 4:
- Year 5:
- Year 6:

= Weekly Cadence

- Reading blocks:
- Problem sheet blocks:
- Tutorial attendance:
- Revision block:
- Buffer time:

= Risk Register

- Workload risks:
- Maths gaps:
- Lab / experiment scheduling:
- Assessment congestion:
EOF

write_file "$ROOT/course/deadlines.typ" <<EOF
#import "../templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "Deadlines and Assessments",
  code: "${COURSE_CODE}",
  stage: "Whole qualification",
  credits: "360",
  start_month: "All starts",
  route: "Assessment tracker",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Assessment Tracker

- Module:
  Assessment:
  Due date:
  Weight:
  Status:

= Exam / EMA Notes

- Remote exams:
- EMA windows:
- Submission checklist:
- Mitigating circumstances:
EOF

write_file "$ROOT/course/formula-book.typ" <<EOF
#import "../templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "Formula Book",
  code: "${COURSE_CODE}",
  stage: "Whole qualification",
  credits: "Reference",
  start_month: "N/A",
  route: "Cross-module",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Mechanics

= Electromagnetism

= Quantum Physics

= Thermodynamics

= Astrophysics and Cosmology

= Mathematical Methods
EOF

write_file "$ROOT/course/glossary.typ" <<EOF
#import "../templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "Glossary and Definitions",
  code: "${COURSE_CODE}",
  stage: "Whole qualification",
  credits: "Reference",
  start_month: "N/A",
  route: "Cross-module",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Terms

- Term:
  Module:
  Meaning / reminder:
EOF

write_file "$ROOT/course/admin/tutor-contacts.typ" <<EOF
#import "../../templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "Tutor and Admin Contacts",
  code: "${COURSE_CODE}",
  stage: "Whole qualification",
  credits: "Admin",
  start_month: "N/A",
  route: "Support",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Contacts

- Role:
  Name:
  Email:
  Notes:
EOF

write_file "$ROOT/course/admin/ou-links.typ" <<EOF
#import "../../templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "OU Links and Portals",
  code: "${COURSE_CODE}",
  stage: "Whole qualification",
  credits: "Admin",
  start_month: "N/A",
  route: "Support",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Core Links

- StudentHome:
- Module websites:
- Library:
- Assessment portal:
- Tutorials / Adobe Connect:
- Careers service:
EOF

write_file "$ROOT/course/capstone/project-planning.typ" <<EOF
#import "../../templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "Project Planning",
  code: "SXP390",
  stage: "Stage 3",
  credits: "30",
  start_month: "February",
  route: "Capstone",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Project Brief

- Topic:
- Supervisor / tutor:
- Research question:
- Deliverables:

= Planning

- Milestone:
  Target date:
  Status:
  Notes:

= Evidence Log

- Key papers:
- Data sources:
- Methods:
- Risks:
EOF

write_file "$ROOT/course/capstone/literature-review.typ" <<EOF
#import "../../templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "Literature Review",
  code: "SXP390",
  stage: "Stage 3",
  credits: "30",
  start_month: "February",
  route: "Capstone",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Scope

= Sources

- Source:
  Contribution:
  Method:
  Follow-up:

= Synthesis
EOF

write_file "$ROOT/course/capstone/final-report.typ" <<EOF
#import "../../templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "Final Project Report Draft",
  code: "SXP390",
  stage: "Stage 3",
  credits: "30",
  start_month: "February",
  route: "Capstone",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Abstract

= Introduction

= Method

= Results

= Discussion

= Conclusion

= References
EOF

create_module() {
  local rel_dir="$1"
  local code="$2"
  local title="$3"
  local stage="$4"
  local credits="$5"
  local start_month="$6"
  local route="$7"

  local dir="$ROOT/modules/$rel_dir/$(slugify "$code-$title")"
  local depth
  local template_rel

  depth="$(awk -F'/' '{print NF + 2}' <<<"$rel_dir")"
  template_rel=""
  for _ in $(seq 1 "$depth"); do
    template_rel="../$template_rel"
  done

  mkdir -p \
    "$dir/assignments" \
    "$dir/lectures" \
    "$dir/problems" \
    "$dir/revision" \
    "$dir/resources" \
    "$dir/build"

  write_file "$dir/notes.typ" <<EOF
#import "${template_rel}templates/ou-physics-template.typ": course-note

#show: doc => course-note(
  title: "${title}",
  code: "${code}",
  stage: "${stage}",
  credits: "${credits}",
  start_month: "${start_month}",
  route: "${route}",
  source_url: "${COURSE_URL}",
  generated: "${CREATED_AT}",
  body: doc,
)

= Module Snapshot

- Module code: ${code}
- Credits: ${credits}
- Start month: ${start_month}
- Route: ${route}
- Tutor:
- Module website:

= Objectives

- Why this module matters:
- What I need to know before starting:
- What success looks like:

= Weekly Notes

== Week 0 Setup

- Textbooks and module materials:
- Software / calculator / tooling:
- Assessment calendar:

= Concepts

- Topic:
  Key idea:
  Confidence:
  Follow-up:

= Equations and Derivations

= Worked Examples

= Tutorials and Questions

- Date:
  Topic:
  Blocking issue:
  Action:

= Assessment Preparation

- TMA plan:
- EMA / exam plan:
- Revision priorities:

= Reflection

- What clicked:
- What is still weak:
- What to revisit next:
EOF

  write_file "$dir/assignments/README.md" <<EOF
# ${code} assignments

Use this directory for TMA, EMA, project drafts, marking feedback, and submission checklists.
EOF

  write_file "$dir/resources/README.md" <<EOF
# ${code} resources

Keep reading lists, external references, datasets, diagrams, and formula sheets here.
EOF
}

create_module "stage-0-access" "Y033" "Science, technology and maths Access module" "Access" "30" "October / February" "Recommended optional access"

create_module "stage-1/standard-start" "S111" "Questions in science" "Stage 1" "60" "October / February" "Standard start"
create_module "stage-1/standard-start" "MST124" "Essential mathematics 1" "Stage 1" "30" "October / February" "Standard start"
create_module "stage-1/standard-start" "SM123" "Physics and space" "Stage 1" "30" "October" "Standard start option"
create_module "stage-1/standard-start" "MST125" "Essential mathematics 2" "Stage 1" "30" "October / February" "Standard start option"

create_module "stage-1/basic-maths-start" "MU123" "Discovering mathematics" "Stage 1" "30" "October / February" "Basic maths start"
create_module "stage-1/basic-maths-start" "MST124" "Essential mathematics 1" "Stage 1" "30" "October / February" "Basic maths start"
create_module "stage-1/basic-maths-start" "MST125" "Essential mathematics 2" "Stage 1" "30" "October / February" "Basic maths start"
create_module "stage-1/basic-maths-start" "SM123" "Physics and space" "Stage 1" "30" "October" "Basic maths start"

create_module "stage-1/advanced-start" "MST124" "Essential mathematics 1" "Stage 1" "30" "October / February" "Advanced start"
create_module "stage-1/advanced-start" "SM123" "Physics and space" "Stage 1" "30" "October" "Advanced start"
create_module "stage-1/advanced-start" "S284" "Astronomy" "Stage 1" "30" "October" "Advanced start option"
create_module "stage-1/advanced-start" "S283" "Planetary science and the search for life" "Stage 1" "30" "October" "Advanced start option"
create_module "stage-1/advanced-start" "MST125" "Essential mathematics 2" "Stage 1" "30" "October / February" "Advanced start option"
create_module "stage-1/advanced-start" "M140" "Introducing statistics" "Stage 1" "30" "October / February" "Advanced start option"

create_module "stage-2/core" "S227" "Core physics" "Stage 2" "60" "October" "Core"
create_module "stage-2/core" "MST224" "Mathematical methods" "Stage 2" "30" "October" "Core"
create_module "stage-2/core" "SXPS288" "Remote experiments in physics and space" "Stage 2" "30" "October" "Core practical"

create_module "stage-3/core" "SM381" "Electromagnetism" "Stage 3" "30" "October" "Core"
create_module "stage-3/core" "SM380" "Quantum physics: fundamentals and applications" "Stage 3" "30" "October" "Core"
create_module "stage-3/options" "S384" "Astrophysics of stars and exoplanets" "Stage 3" "30" "October" "Option"
create_module "stage-3/options" "MST374" "Computational applied mathematics" "Stage 3" "30" "October" "Option"
create_module "stage-3/options" "S385" "Cosmology and the distant Universe" "Stage 3" "30" "October" "Option"
create_module "stage-3/options" "MS327" "Deterministic and stochastic dynamics" "Stage 3" "30" "October" "Option"
create_module "stage-3/options" "MST326" "Mathematical methods and fluid mechanics" "Stage 3" "30" "October" "Option"
create_module "stage-3/project" "SXP390" "Science project course: radiation and matter" "Stage 3" "30" "February" "Required final project"

mkdir -p "$ROOT/archive"

printf 'Created OU Physics study workspace at %s\n' "$ROOT"
