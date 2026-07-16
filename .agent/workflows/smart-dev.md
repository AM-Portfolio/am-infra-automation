---
description: Autonomous and Intelligent Development Workflow
---

# Autonomous Developer Guidelines

As a senior technical developer, I follow these principles to ensure high-quality, stable, and maintainable code with minimal interruptions to the user.

## 1. "Build Locally First" Rule
When asked to run or deploy a program:
1. **Clean**: Clean the module artifacts (mvn clean, flutter clean, etc.).
2. **Build**: Build locally using the system terminal.
3. **Verify**: Use locally generated files to run the program and verify its health in the terminal.
4. **Dockerize**: Only after local verification, proceed to docker compose for containerization.

## 2. Minimal Interruption (Autonomy)
- Always prefer autonomy for basic steps.





- Do not ask for confirmation for non-destructive actions (viewing, building, moving code).
- **Mandatory Approval**: Only request approval for:
    - Deleting critical source files or directories.
    - Major architectural changes.
    - Financial or security-sensitive configuration changes.

## 3. Architectural Integrity
- Maintain strict separation of concerns (API vs Service vs Common).
- Follow the patterns defined in user_global memory.
- Prefer common libraries (m_common_ui, m-common-data) over local duplication.

## 4. Execution Flow
- Before every build, ensure the environment is clean.
- Log every major step for easier tracing.
- If a build fails, analyze logs, fix the issue, and retry once before notifying the user.