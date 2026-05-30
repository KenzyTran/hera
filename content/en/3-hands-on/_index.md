---
title: "Hands-on"
date: 2025-01-01
weight: 3
chapter: true
pre: "<b>3. </b>"
---

### Hands-on

# Hands-on Steps

In this section, we will go through the main steps of the workshop.

{{% notice tip %}}
**Before you start — your shell.** Every `bin/*.sh` script is **bash**, while `terraform` / `aws` / `cdk` / `docker` are cross-platform. Recommended:

- **macOS / Linux:** use the default terminal.
- **Windows:** use **Git Bash** (ships with Git for Windows) or **WSL** so the `.sh` scripts run exactly as documented. Two Git Bash gotchas:
  - AWS commands with an argument starting with `/` (e.g. `/aws/bedrock-agentcore/...`) get rewritten into a Windows path → `InvalidParameterException`. Prefix that command with `MSYS_NO_PATHCONV=1`.
  - If you use PowerShell instead of Git Bash: env-var syntax differs (`$env:VAR="x"` instead of `export VAR=x`), and call scripts via `bash bin/xxx.sh`.
- **General note:** the command blocks are meant to be copy-pasted. Anything in `<...>` form (e.g. `<your-runtime-id>`) is a **placeholder** — replace it with the real value and **do not paste the literal `<` `>`** (bash treats `<` as a redirect and fails with "No such file or directory").
{{% /notice %}}

{{% children %}}
