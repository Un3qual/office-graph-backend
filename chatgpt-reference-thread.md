# Me
Help me spitball my new AI startup idea and flesh it out. It's a task/todo tracker, but graph based and designed for agents and humans to work together.

plan is turned into deeply nested tree of boards 
plan is for writing spec documents so agents can chew through it autonomously
platform could also be for autonomous agents to work on plans
could also connect to CI/CD, and error logging tools like sentry to automatically add tasks to a queue to fix bugs

spitball:
- as a "pre-plan" (a plan for what decisions need to be made) is developed, that part of tree gets deeper, (results in questions queued for devs to look through), then ???
- maybe like each node is a task or a question...
- its a graph
    - dont know if directional
    - maybe its like
        - phase 1 is building the graph
        - phase 2 is making it a 
            - list of trees? so that parallel work can happen most efficiently 
        - but due to having multiple teams, subteams, etc both phases would be happening at the same time
    - maybe like something is complete/collapsed when all of its "children" are complete/collapsed (which could either mean all questions are answered and done (hidden/deleted) and all of the subtasks are complete, or when all of the node's children are complete meaning that anything (incl. questions) can be marked as complete
- i at least know the kinds of some of the things in it will be task, plan, question
    - maybe it matters what is a node and what is an edge
    - but like can some things be "feature", "campaign", "goal", etc
        - maybe its goals vs tasks?
- maybe every node is a ???? and its children are a list of questions, and sub-tasks? and each time a question is answered, it either turnes into a sub-task(idk) or more questions, or modifies an attribute/tag/label on that node.
    - a question can be 
    - questions, tasks, and any type of node or edge can be manually added, but the magic is AI adding nodes
- i think the key is gonna be differentiating goals vs tasks vs plans vs questions, and maybe like an auton work boundary, and what nodes can have what type of edges with other nodes and in what direction
- a task can be marked (and auto-detected) as ready for agent, the agent will try, an
- maybe a node's task children are morphed into a plan
    - or a given number of tasks can be selected and the user could press "make a plan" and a plan node would be added with an ai generated plan that would basically be a prompt for an agent or multiple plans for multiple agents in parallel
- is it like a node's state follows: goal -> task -> (question) -> plan -> milestone?
- the finalize plan thing is good, but how would we differentiate "do this one thing as a task for...
- tasks can be selected, and you can either "generate plan and execute in 1 run", "generate a nonvolatile long-term plan, and execute each task in sequence", "generate plans for each and run in parallel", or "allow agent to make its own subagent tree and go nuts" (with limits of course), and if any of the sub-sub-*-*-agents get stuck, they ask a question and it gets added to a question queue (questions can be enabled or disabled for a run), 
- for code stuff, i think the user has to have the option to work on it locally in their own editor
- tasks or plans or nodes? or something can have success criteria

# ChatGPT
MVP for a seed round

For a seed round, the MVP should not be a full graph-based project management platform.

It should prove one narrow claim:

Engineering teams have a real, recurring problem turning messy bugs/specs/incidents into clear, safe, verifiable work for humans and agents — and your product solves that better than Linear, Jira, GitHub, Sentry, or coding agents alone.

Seed investors will not need every feature. They will need evidence that the wedge is real, repeatable, and can expand. For AI SaaS specifically, investors are now looking beyond “we use AI” and toward deep workflow integration, retention, usage growth, unit economics, and defensibility. CRV’s 2026 AI SaaS investment guide is explicit that AI SaaS investors care about variable inference costs, real engagement beyond experimentation, workflow depth, and whether the product would still have value without being a thin model wrapper.  

⸻

The seed-round MVP thesis

Product category

Do not pitch it as:

“AI todo tracker.”

Pitch it as:

An agent-readiness layer for software teams.

Or:

A control plane that turns bugs, specs, and incidents into agent-ready work packets with human decisions, constraints, and verification built in.

The MVP should focus on this loop:

Signal or messy request
→ structured work graph
→ blocking questions
→ agent-ready task packet
→ handoff to agent/human
→ PR/test/Sentry evidence
→ verified completion

That is the loop you need to prove.

⸻

The best MVP wedge

Start with: Sentry/GitHub/CI → agent-ready work packets

This is stronger than starting with arbitrary product planning.

Why?

Reason	Explanation
High pain	Bugs, CI failures, and production issues are urgent
Concrete ROI	Faster triage, faster PRs, fewer repeated explanations
Clear data sources	GitHub, Sentry, CI logs, stack traces, PR history
Natural agent use case	Coding agents are already being used for bug fixes
Verifiable outcome	PR opened, tests passed, Sentry issue resolved
Narrow enough for MVP	You avoid rebuilding Jira/Linear immediately

Sentry is already pushing hard into this space: Seer Autofix reads stack traces, traces root cause through the codebase, drafts fixes, can run automatically on issues it believes are fixable, and hands context to Cursor, Copilot, and Claude.  

That means your MVP cannot just be:

“Sentry issue becomes AI fix.”

That is already taken.

Your wedge should be:

Sentry/GitHub issues become structured, permissioned, verifiable work packets that humans and agents can safely execute.

The difference is not the fix. The difference is the work graph, decision queue, readiness score, and completion evidence.

⸻

What the MVP actually does

MVP name, conceptually

Call it something like:

Agent Readiness Console

Internally, the graph exists. But externally, the MVP feels like a command center.

User persona

Start with:

Tech leads / engineering managers at small-to-mid software teams using GitHub + Sentry + Linear/Jira + Cursor/Codex/Copilot/Claude Code.

Ideal early customer:

* 5–50 engineers
* already using AI coding tools
* has production bugs and CI failures
* hates writing good tickets
* wants agents to help but does not trust them with vague work
* uses GitHub and Sentry
* probably uses Linear or Jira, but you do not need to replace either

⸻

MVP workflow

1. Connect tools

Initial integrations:

Integration	Purpose
GitHub	repos, issues, PRs, commits, CI status
Sentry	production errors, traces, stack frames, issue frequency
Linear or Jira	existing work items
Slack	optional intake/question notifications
Cursor/Codex/Copilot/Claude Code export	execution handoff

For MVP, I would start with:

GitHub + Sentry + Linear

Then add Jira once enterprise buyers demand it.

Linear is already positioning itself as “the product development system for teams and agents,” with workflows shared by humans and agents from drafting PRDs to pushing PRs.   So your MVP should integrate with Linear first rather than try to replace it.

⸻

2. Ingest a real bug or issue

The user imports a Sentry issue, GitHub issue, failing CI run, or Linear ticket.

Example:

Sentry Issue:
OAuth callback throws 500 on invalid state parameter.
143 users affected in 24 hours.
First seen after PR #812.

Your system creates a structured work packet:

Bug: OAuth callback throws 500 on invalid state
Evidence:
- Sentry issue #4921
- Stack trace
- Affected release
- Suspected PR #812
- Relevant files
Likely root area:
- Auth callback handler
- OAuth state store
- Session fallback behavior
Blocking question:
- Should invalid state redirect to login or return 400?
Success criteria:
- Invalid state no longer throws 500
- Regression test added
- Existing OAuth tests pass
- Sentry issue quiet after deploy
Agent readiness:
Medium-high

This is the MVP magic.

⸻

3. Generate a question queue

The MVP should surface only the questions that prevent safe execution.

Example:

Question:
When OAuth state is invalid, should the app:
A. Return 400
B. Redirect to login with an error banner
C. Restart OAuth flow automatically
Recommended:
B
Reason:
Preserves user flow and avoids exposing implementation details.

The user answers. The task becomes more agent-ready.

This is central. Investors should see that your product is not “AI makes tasks.” It is:

AI identifies the missing decisions that block delegation.

⸻

4. Score “agent readiness”

Each imported issue gets a readiness state:

Status	Meaning
Ready for agent	Clear objective, context, constraints, tests
Needs human answer	Blocked by missing decision
Needs senior review	Risky architecture/auth/data change
Human-only	Too ambiguous, too broad, or too risky
Investigate-only	Agent can inspect but not modify

Example:

Agent readiness: 82/100
Ready because:
✓ Stack trace available
✓ Relevant files identified
✓ Scope is narrow
✓ Test path exists
✓ No schema changes needed
Remaining risk:
- Auth behavior decision required

This is a seed-worthy primitive. It gives you a crisp wedge.

⸻

5. Generate an executable work packet

The MVP should output a task packet that can be used by:

* a human engineer
* Cursor
* Claude Code
* Codex
* GitHub Copilot
* a custom agent later

Example packet:

# Task: Fix OAuth callback crash on invalid state
## Objective
Handle invalid OAuth state without throwing a 500.
## Context
Sentry issue #4921 began after PR #812. Stack trace points to
src/auth/oauth_callback.ts when state lookup returns null.
## Constraints
- Do not modify database schema.
- Do not change session expiration behavior.
- Prefer redirect to login with error banner unless impossible.
## Relevant files
- src/auth/oauth_callback.ts
- src/auth/state_store.ts
- tests/auth/oauth_callback_test.ts
## Success criteria
- Invalid state returns login redirect with error banner.
- Regression test added.
- Existing OAuth tests pass.
- Sentry issue receives no new events after deploy.
## Escalation
Ask before changing session middleware.

This alone is useful.

Even if your agent execution is thin at first, the work packet is valuable.

⸻

6. Handoff to existing agents

Do not build your own coding agent for MVP.

Use existing tools.

Execution buttons:

[Open in Cursor]
[Send to Claude Code]
[Send to Codex]
[Create GitHub issue]
[Create Linear issue]
[Copy task packet]
[Create branch + PR checklist]

This keeps scope small and avoids competing directly with coding-agent vendors before you have to.

There is already evidence that AI coding agents have different roles in PR workflows, with humans still retaining merge governance in practice. A recent empirical study of 29,585 PR lifecycles found that collaborator-style tools can initiate work, but merge authority remains overwhelmingly human.  

That supports your positioning:

Agents can initiate and produce work. Humans still need governance, review, and verification.

Your product becomes the governance layer.

⸻

7. Track verification evidence

After the work is done, the MVP pulls back:

Evidence	Source
PR opened	GitHub
Tests passed	GitHub Actions
Review approved	GitHub
PR merged	GitHub
Sentry issue quiet	Sentry
Linear issue closed	Linear

Then it marks the work as:

Implemented
Verified
Needs monitoring
Failed verification

This matters because empirical work on AI-generated PRs shows integration problems are real. A 2026 study of fix-related AI-agent PRs found that test failures and duplicate/prior resolutions were among the most common reasons AI-agent PRs were closed without merging.   Another study of 61,837 GitHub Actions runs triggered by AI-bot PRs found substantial agent-dependent differences in CI reliability and argued for better safeguards around agentic workflows.  

That is your investor argument:

The bottleneck is no longer generating code. The bottleneck is selecting, scoping, governing, and verifying agent work.

⸻

What to build for the seed MVP

Must-have features

1. Intake

Import Sentry issue
Import GitHub issue
Import failing GitHub Actions run
Import Linear issue
Paste messy request/spec manually

2. Work packet generator

Generates:

Objective
Context
Relevant files
Constraints
Questions
Success criteria
Risk level
Agent readiness score
Suggested execution mode

3. Question queue

A simple inbox:

3 questions blocking agent work
5 questions blocking planning
2 questions blocking verification

Each question should have:

question
why it matters
recommended answer
impact of each option
source/evidence

4. Mini graph

Not a full graph editor.

Just enough to show:

Signal → Bug → Question → Decision → Task → Check → Evidence

The MVP graph can be mostly read-only.

5. Agent handoff

Start with exports:

Copy markdown packet
Open GitHub issue
Create Linear issue
Send to Cursor/Claude/Codex via supported handoff where possible

Do not overbuild here.

6. Verification dashboard

For each work item:

No PR yet
PR opened
CI failed
CI passed
Review needed
Merged
Monitoring in Sentry
Verified

7. Audit trail

Every AI-generated node should show:

Generated from Sentry issue #4921
Generated from PR #812
Generated from user answer on June 3, 2026

Seed investors will care about trust. This helps.

⸻

What not to build yet

Avoid these for MVP:

Do not build yet	Why
Full Jira/Linear replacement	Too much surface area
Arbitrary graph editor	Too complex and not the wedge
Built-in coding agent	Expensive, crowded, not necessary
Full roadmap/planning suite	Hard to prove quickly
Multi-team permissions	Enterprise later
Deep analytics dashboard	Not needed to prove the loop
Custom CI system	Integrate instead
General-purpose personal todo app	Wrong market
Agent marketplace	Premature
Mobile app	Not needed

The seed MVP should be narrow and sharp.

⸻

The minimum product surface

I would build exactly these screens:

1. Inbox

New signals:
- 12 Sentry issues
- 3 failing CI runs
- 8 stale Linear issues
- 4 GitHub issues with insufficient context

Each item gets a suggested classification:

Ready for agent
Needs human answer
Needs triage
Duplicate
Ignore

⸻

2. Question Queue

Questions blocking execution:
1. Should invalid OAuth state redirect or 400?
2. Can the agent modify auth middleware?
3. Should this fix be backported?

This is probably the highest-value screen.

⸻

3. Work Packet View

A single page for one task:

Objective
Evidence
Relevant code
Constraints
Success criteria
Risk
Agent readiness
Execution options

⸻

4. Execution/Handoff View

Send to:
- Cursor
- Claude Code
- Codex
- GitHub Copilot
- Human engineer
Mode:
- Investigate only
- Draft plan
- Open PR
- Work locally

⸻

5. Verification View

PR status
CI status
Review status
Deploy status
Sentry status
Completion evidence

⸻

Seed-round demo script

A strong demo would look like this:

Step 1: Import production bug

Sentry issue: OAuth callback crash

The product creates:

Bug node
Evidence
Likely files
Risk level
Success criteria
Blocking question

Step 2: Human answers one question

Invalid OAuth state should redirect to login with an error banner.

The product updates:

Decision recorded
Task becomes agent-ready
Work packet regenerated

Step 3: Send to coding agent

Click:

Open in Cursor

or:

Create GitHub issue for Copilot

Step 4: Agent opens PR

The product ingests:

PR #914 opened
Tests running

Step 5: CI fails

The product creates:

Check failed: auth callback regression test
New task: fix failing test expectation

Step 6: Agent/human fixes it

CI passes.

Step 7: Verification closes loop

The product shows:

PR merged
CI passed
Sentry issue quiet for 24h
Task verified
Parent reliability goal updated

That is the whole seed-round story.

⸻

What traction you need for seed

This depends on team, market, and investor profile, but for this specific company I would aim for one of these before raising seed.

Good seed signal

5–10 design partners
2–3 teams using it weekly
At least 100 real issues/work packets processed
At least 20 tasks handed off to agents/humans
Clear evidence that task prep/triage time dropped

Strong seed signal

10–20 teams using it
3–5 paying customers
$10k–$50k MRR or equivalent paid pilots
Hundreds of work packets generated
Measurable reduction in triage time
Measurable increase in agent PR acceptance / completion

Very strong seed signal

$500k+ ARR run-rate or signed annual pilots
Usage expanding inside teams
Customers asking to connect more repos/tools
Repeated weekly habit among eng leads
Evidence that agents complete more tasks successfully with your packets than without them

I would not present ARR as the only bar. For an AI/devtools seed, a smaller number of intense, credible design partners can be enough if the usage is deep and the founders are strong. But you need more than a pretty demo. Investors are now specifically watching whether AI products are experimental toys or retained workflows.  

⸻

The metric investors should care about

Your flagship metric should not be:

Tasks created

That is a vanity metric.

Better metrics:

1. Agent-ready conversion rate

% of messy issues/specs converted into agent-ready work packets

2. Question resolution rate

% of blocking questions answered by humans

3. Time to agent-ready

Median time from incoming signal to executable task

4. Agent success uplift

PR acceptance / CI pass / merge rate with your packets
vs. baseline agent use without your packets

5. Human triage time saved

Minutes saved per bug/spec/issue

6. Verification completion rate

% of work marked done with linked evidence

7. Repeat usage

Weekly active eng leads
Work packets per team per week
Questions answered per team per week

The strongest metric is probably:

Agent work completion rate improves when tasks are compiled through your system.

That is a real moat if you can prove it.

⸻

MVP data model

For MVP, use a simple graph underneath.

Node types

Signal
Question
Decision
Task
Check
Artifact
Evidence

Do not include every future type yet.

Skip:

Campaign
Goal
Milestone
Feature
Requirement
Risk
Plan

Those can come later, or be represented as tags/attributes at first.

Edge types

generated_from
raises
answers
blocked_by
requires
validates
produced
evidence_for
duplicates

That is enough.

Core state machine

New signal
→ Needs triage
→ Needs answer
→ Agent-ready
→ In execution
→ Needs review
→ Monitoring
→ Verified

Keep it boring.

The product can become more graph-rich later.

⸻

Technical MVP architecture

Backend

Use whatever lets you move fastest. Since you are strong in Elixir, Phoenix is a good fit.

Recommended architecture:

Phoenix app
Postgres
pgvector or external vector DB if needed
Oban for background jobs
GitHub/Sentry/Linear webhooks
LLM orchestration layer
Graph stored relationally

You do not need Neo4j at first.

A graph can be stored in Postgres:

nodes table
edges table
artifacts table
runs table
questions table
decisions table

Use recursive CTEs where needed. Move to graph-specific infrastructure only if necessary.

LLM layer

Use models for:

classification
summarization
question generation
success criteria generation
work packet generation
risk assessment
deduplication

But make outputs structured and inspectable.

Agent layer

Initially:

No custom agent
Just export/handoff

Later:

Agent runner
Sandbox
Branch creation
PR generation
Tool permissions

Do not spend seed-MVP time reinventing Codex/Cursor/Claude Code.

⸻

Pricing for MVP pilots

Do not price like a personal productivity app.

Possible pricing:

Early paid pilot

$500–$2,000/month/team

For small teams.

More serious pilot

$5,000–$15,000/year/team

For startups with 10–50 engineers.

Enterprise later

Per-engineer + usage
or
platform fee + agent-run/packet volume

Be careful with AI cost. AI SaaS has variable inference costs, and investors are explicitly looking at whether pricing matches usage-based cost structure.  

A good pricing unit might be:

per connected repo
+ per active engineering seat
+ usage tier for generated work packets / agent handoffs

Avoid unlimited heavy agent usage unless you know your margins.

⸻

Seed deck story

Your seed deck should not say:

“Project management is broken.”

Too generic.

Say:

“Coding agents are getting powerful, but teams cannot safely delegate vague work to them.”

Then:

1. Agents can write code.
2. But most engineering work starts as ambiguous bugs, incidents, specs, and decisions.
3. Existing PM tools track tasks, but they do not compile ambiguity into agent-ready work.
4. This causes failed PRs, human rework, bad scoping, and low trust.
5. We create the missing agent-readiness layer.

Then show the loop:

Signal → Question → Decision → Work Packet → Agent/Human → Evidence → Verified

⸻

What the seed MVP should prove

By the time you raise seed, you want to credibly prove:

1. The problem is real

Teams are already trying to use coding agents, but tasks are too vague and agent results are inconsistent.

2. The workflow is frequent

Bugs, CI failures, product requests, and support escalations happen every week.

3. Your product improves delegation

Tasks compiled by your system are easier for humans and agents to complete.

4. The graph is not a gimmick

The graph enables question tracking, decision history, dependency management, and verification.

5. You are not just a wrapper

The durable asset is:

structured work graph
decision history
success criteria
verification evidence
team-specific execution patterns

This matters because investors increasingly view thin AI wrappers as fragile, especially when foundation model providers and incumbents can ship adjacent features.  

⸻

The MVP in one sentence

A GitHub/Sentry/Linear-connected app that turns messy bugs and engineering requests into structured, agent-ready work packets with blocking questions, autonomy boundaries, success criteria, and verification evidence.

That is the seed MVP.

Not the whole company.

The whole company is the graph-native operating system for human-agent software teams.

But the MVP should prove the smallest painful loop:

Can you make agent delegation safer, clearer, and more verifiable than the current mess of tickets, Slack threads, Sentry alerts, and PR comments?

# Me
What does the architecture look like?

# ChatGPT
Recommended architecture

For the MVP, I would use a modular monolith with a graph-shaped data model, not a microservice zoo.

Given your Elixir background, a very reasonable stack is:

Phoenix / LiveView or Phoenix API
Postgres
Oban for jobs
GitHub/Sentry/Linear webhooks
LLM provider abstraction
Object storage for artifacts
Optional vector search

Do not start with Neo4j, Kafka, Kubernetes, or a custom agent runtime unless you hit a real need.

The architecture should be:

External tools
  ↓
Integration ingestion
  ↓
Canonical event log
  ↓
Work graph core
  ↓
AI compiler / planner
  ↓
Question queue + work packet generator
  ↓
Agent/human handoff
  ↓
Verification + evidence tracking

⸻

1. High-level system diagram

┌──────────────────────────────────────────────────────────┐
│                    External Systems                      │
│                                                          │
│ GitHub   Sentry   Linear/Jira   CI   Slack   Docs/Specs  │
└───────────────┬───────────────┬───────────────┬──────────┘
                │               │               │
                ▼               ▼               ▼
┌──────────────────────────────────────────────────────────┐
│                 Integration Adapters                     │
│                                                          │
│ - Webhooks                                               │
│ - API sync jobs                                          │
│ - OAuth installations                                    │
│ - Rate-limit handling                                    │
│ - External ID mapping                                    │
└──────────────────────────────┬───────────────────────────┘
                               ▼
┌──────────────────────────────────────────────────────────┐
│                  Canonical Event Log                     │
│                                                          │
│ External events normalized into internal events:          │
│ - sentry.issue.created                                   │
│ - github.pr.opened                                       │
│ - github.check.failed                                    │
│ - linear.issue.updated                                   │
└──────────────────────────────┬───────────────────────────┘
                               ▼
┌──────────────────────────────────────────────────────────┐
│                    Work Graph Core                       │
│                                                          │
│ Nodes: Signal, Question, Decision, Task, Check, Artifact │
│ Edges: blocks, answers, validates, generated_from, etc.  │
│ State machine, permissions, audit trail                  │
└──────────────────────────────┬───────────────────────────┘
                               ▼
┌──────────────────────────────────────────────────────────┐
│                 AI Work Compiler                         │
│                                                          │
│ - Triage                                                 │
│ - Deduplication                                          │
│ - Question generation                                    │
│ - Agent-readiness scoring                                │
│ - Work packet generation                                 │
│ - Success criteria generation                            │
└──────────────────────────────┬───────────────────────────┘
                               ▼
┌──────────────────────────────────────────────────────────┐
│                      Product UI                          │
│                                                          │
│ Inbox | Question Queue | Work Packets | Graph | Runs     │
└──────────────────────────────┬───────────────────────────┘
                               ▼
┌──────────────────────────────────────────────────────────┐
│                 Execution / Handoff Layer                │
│                                                          │
│ Cursor, Claude Code, Codex, Copilot, GitHub issue,       │
│ local CLI, human engineer                                │
└──────────────────────────────┬───────────────────────────┘
                               ▼
┌──────────────────────────────────────────────────────────┐
│                Verification / Evidence Layer             │
│                                                          │
│ PR merged, CI passed, tests added, Sentry quiet,          │
│ human approved, deploy succeeded                         │
└──────────────────────────────────────────────────────────┘

⸻

2. Core principle: AI proposes graph mutations

The LLM should not directly mutate the database.

Use this pattern:

External event
→ deterministic ingestion
→ AI proposes graph change
→ validation layer checks proposal
→ accepted proposal becomes database mutation
→ audit trail records source and reason

For example:

Sentry issue imported
→ AI suggests:
   - create Bug Task
   - create Question
   - create Check
   - link relevant GitHub PR
→ app validates:
   - valid node types?
   - valid edge types?
   - duplicate?
   - confidence threshold?
   - permissions okay?
→ graph mutation committed

This prevents the system from becoming a pile of hallucinated tasks.

⸻

3. Main backend modules

I would split the backend into these bounded modules.

1. Identity / orgs / permissions

Handles:

users
organizations
teams
repo access
integration installs
role-based permissions
agent permissions

You need this early because agent autonomy depends on permissions.

Example permission concepts:

can_view_repo_context
can_create_task
can_answer_question
can_approve_decision
can_run_agent
can_allow_code_changes
can_merge_or_verify

⸻

2. Integration adapters

Each external tool gets an adapter.

Integrations.GitHub
Integrations.Sentry
Integrations.Linear
Integrations.Jira
Integrations.Slack

Adapters should translate external data into canonical internal events.

Example:

%ExternalEvent{
  source: :sentry,
  source_id: "issue_4921",
  type: "sentry.issue.created",
  organization_id: org_id,
  payload: %{...},
  occurred_at: timestamp
}

The graph core should not care about Sentry’s exact payload shape.

⸻

3. Event ingestion

Use an append-only event table.

external_events
---------------
id
organization_id
source
source_event_type
external_id
payload_json
payload_hash
occurred_at
received_at
processed_at
processing_status

This gives you:

* replayability
* debugging
* deduplication
* audit history
* safer webhook handling

This is especially important for GitHub and Sentry webhooks, which may retry or arrive out of order.

⸻

4. Work graph core

This is the heart of the product.

MVP node types

Signal
Question
Decision
Task
Check
Artifact
Evidence
Run

MVP edge types

generated_from
raises
answers
blocked_by
depends_on
requires
validates
produced
evidence_for
duplicates
relates_to

This is enough for the seed MVP.

⸻

4. Postgres graph schema

You do not need a graph database yet.

Use Postgres.

nodes

CREATE TABLE nodes (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL,
  risk_level TEXT,
  readiness_score INT,
  properties JSONB NOT NULL DEFAULT '{}',
  created_by_type TEXT NOT NULL, -- user, ai, integration, system
  created_by_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

edges

CREATE TABLE edges (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL,
  from_node_id UUID NOT NULL REFERENCES nodes(id),
  to_node_id UUID NOT NULL REFERENCES nodes(id),
  type TEXT NOT NULL,
  properties JSONB NOT NULL DEFAULT '{}',
  confidence FLOAT,
  created_by_type TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

node_events

This is your audit trail.

CREATE TABLE node_events (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL,
  node_id UUID REFERENCES nodes(id),
  event_type TEXT NOT NULL,
  actor_type TEXT NOT NULL, -- user, ai, system, integration
  actor_id TEXT,
  payload JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

artifacts

Artifacts are external or internal objects.

CREATE TABLE artifacts (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL,
  source TEXT NOT NULL, -- github, sentry, linear, internal, uploaded
  external_id TEXT,
  artifact_type TEXT NOT NULL, -- pr, issue, commit, stack_trace, file, doc
  title TEXT,
  url TEXT,
  content_ref TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

node_artifacts

CREATE TABLE node_artifacts (
  node_id UUID NOT NULL REFERENCES nodes(id),
  artifact_id UUID NOT NULL REFERENCES artifacts(id),
  relationship TEXT NOT NULL, -- evidence, context, output, source
  PRIMARY KEY (node_id, artifact_id, relationship)
);

⸻

5. Why Postgres is enough

For MVP, your graph queries are mostly:

Show children of this node
Show blockers
Show tasks generated from this signal
Show checks validating this task
Show evidence for completion
Show unresolved questions blocking agent readiness

These are easy with indexed edge tables.

Add indexes:

CREATE INDEX edges_from_idx ON edges(from_node_id, type);
CREATE INDEX edges_to_idx ON edges(to_node_id, type);
CREATE INDEX nodes_org_type_status_idx ON nodes(organization_id, type, status);
CREATE INDEX nodes_properties_gin_idx ON nodes USING GIN(properties);

Only consider Neo4j or a graph DB if you later need:

* deep graph algorithms
* heavy cross-project dependency traversal
* complex path queries
* graph centrality / clustering / impact analysis
* interactive graph analytics at scale

Not needed for seed MVP.

⸻

6. AI compiler architecture

The AI part should be a set of specialized pipelines, not one giant “agent.”

Pipeline 1: Triage classifier

Input:

Sentry issue / GitHub issue / CI failure / Linear issue

Output:

{
  "classification": "bug",
  "severity": "medium",
  "recommended_action": "create_task",
  "confidence": 0.82
}

⸻

Pipeline 2: Work graph proposal generator

Input:

Signal + repo metadata + linked PRs + stack trace

Output:

{
  "nodes": [
    {
      "type": "task",
      "title": "Fix OAuth callback crash on invalid state"
    },
    {
      "type": "question",
      "title": "Should invalid OAuth state redirect or return 400?"
    },
    {
      "type": "check",
      "title": "Regression test covers invalid OAuth state"
    }
  ],
  "edges": [
    {
      "from": "question_temp_1",
      "to": "task_temp_1",
      "type": "blocked_by"
    },
    {
      "from": "check_temp_1",
      "to": "task_temp_1",
      "type": "validates"
    }
  ]
}

Then your deterministic validation layer checks it.

⸻

Pipeline 3: Question generator

Generates only questions that matter.

Bad:

What should the UI look like?

Good:

When OAuth state is invalid, should the user be redirected to login or receive a 400 response?

Each question should include:

why this matters
recommended answer
risk of proceeding without answer
which tasks it blocks

⸻

Pipeline 4: Agent-readiness scorer

Scores based on deterministic + AI factors.

Deterministic inputs

Has objective?
Has linked evidence?
Has relevant files?
Has success criteria?
Has unresolved blocking questions?
Has tests?
Touches risky areas?
Requires schema/auth/payment changes?

AI inputs

Ambiguity level
Scope clarity
Risk assessment
Likely required context
Suggested autonomy mode

Output:

{
  "score": 82,
  "status": "ready_for_agent",
  "reasons": [
    "Narrow bug scope",
    "Stack trace available",
    "Regression test path likely exists"
  ],
  "risks": [
    "Auth behavior decision needed"
  ],
  "recommended_mode": "draft_pr"
}

⸻

Pipeline 5: Work packet compiler

This is the most important pipeline.

It turns graph context into a durable task packet.

Input:

Task node
Linked signal
Linked decisions
Linked requirements
Linked checks
Linked artifacts
Relevant code metadata
Permissions

Output:

# Task
...
# Objective
...
# Context
...
# Constraints
...
# Relevant files
...
# Success criteria
...
# Escalation rules
...

This is the thing you send to humans or agents.

⸻

7. Graph mutation proposal format

I would create an internal format called something like GraphPatch.

The LLM never writes to tables. It emits a patch.

{
  "reason": "Sentry issue indicates a production OAuth crash",
  "confidence": 0.86,
  "operations": [
    {
      "op": "create_node",
      "temp_id": "task_1",
      "node_type": "task",
      "title": "Fix OAuth callback crash",
      "properties": {
        "risk_level": "medium"
      }
    },
    {
      "op": "create_node",
      "temp_id": "question_1",
      "node_type": "question",
      "title": "Should invalid OAuth state redirect or return 400?"
    },
    {
      "op": "create_edge",
      "from": "task_1",
      "to": "question_1",
      "edge_type": "blocked_by"
    }
  ]
}

Then:

GraphPatch
→ validate schema
→ resolve temp IDs
→ dedupe
→ permission check
→ maybe require human approval
→ commit transaction

This pattern is very important.

⸻

8. State machines

You should have explicit state machines. Avoid loose statuses.

Signal state

new
triaged
converted
ignored
duplicate

Question state

open
answered
superseded
dismissed

Task state

draft
needs_context
needs_human_answer
ready_for_agent
ready_for_human
in_execution
needs_review
monitoring
verified
failed
archived

Check state

pending
running
passed
failed
waived

Run state

created
queued
in_progress
blocked
completed
failed
cancelled

The graph can be flexible, but states should be constrained.

⸻

9. Execution layer

For MVP, the execution layer should mostly be handoff, not full autonomous execution.

Handoff targets

Create GitHub issue
Create Linear issue
Copy markdown packet
Open local CLI task bundle
Send to Claude Code / Cursor / Codex where possible
Create branch with task context file

Local CLI

A CLI would be valuable even early.

Example:

taskgraph pull TASK-123

Creates:

.taskgraph/TASK-123/
  task.md
  context.md
  success_criteria.md
  decisions.md
  artifacts.json
  policy.json

Then:

taskgraph submit TASK-123

Pushes back:

branch name
commits
test results
PR URL
notes
new questions

This is a strong wedge because it lets humans and local coding agents use your structured context.

⸻

10. Verification architecture

Verification should be separate from execution.

A task is not complete because an agent says it is complete.

Completion comes from evidence.

Evidence sources

GitHub PR opened
GitHub PR merged
GitHub Actions passed
Specific test added
Sentry issue resolved
Sentry event volume decreased
Human review approved
Deploy succeeded

Evidence nodes

Represent evidence as graph nodes or artifacts linked to checks.

Task: Fix OAuth callback crash
  validated_by → Check: Regression test passes
  evidence_for → GitHub Actions run #123
  evidence_for → PR #914 merged
  evidence_for → Sentry issue quiet for 24h

This gives you a defensible product difference.

Most tools track status. You track proof.

⸻

11. Suggested application modules

In Elixir-ish terms:

MyApp.Accounts
MyApp.Orgs
MyApp.Integrations
MyApp.Ingestion
MyApp.Graph
MyApp.GraphPatches
MyApp.WorkPackets
MyApp.Questions
MyApp.AgentReadiness
MyApp.Executions
MyApp.Verification
MyApp.Audit
MyApp.Notifications

A possible Phoenix context layout:

lib/my_app/
  accounts/
  orgs/
  integrations/
    github/
    sentry/
    linear/
  ingestion/
  graph/
    node.ex
    edge.ex
    graph_patch.ex
    graph_service.ex
  ai/
    provider.ex
    prompts/
    pipelines/
      triage.ex
      graph_patch_generator.ex
      question_generator.ex
      readiness_scorer.ex
      work_packet_compiler.ex
  work_packets/
  executions/
  verification/
  audit/
  notifications/

⸻

12. Job architecture

Use Oban jobs for everything asynchronous.

IngestWebhookJob
SyncGitHubRepoJob
SyncSentryIssueJob
ProcessExternalEventJob
GenerateGraphPatchJob
ScoreAgentReadinessJob
CompileWorkPacketJob
VerifyTaskJob
SyncPRStatusJob
SyncSentryStatusJob
NotifyQuestionOwnerJob

Important: make jobs idempotent.

Every job should be safe to retry.

⸻

13. Data flow: Sentry issue to verified task

Here is the full MVP flow.

1. Sentry webhook arrives
2. Store raw webhook as external_event
3. Normalize into Signal node
4. Enqueue AI triage job
5. AI proposes GraphPatch:
   - Task
   - Question
   - Check
   - Relevant artifacts
6. Validate and commit GraphPatch
7. Score agent readiness
8. Show in Inbox / Question Queue
9. Human answers blocking question
10. Decision node is created
11. Task readiness recalculated
12. Work packet compiled
13. User sends packet to agent/human
14. GitHub PR is opened
15. GitHub webhook links PR artifact to task
16. CI passes/fails
17. Check nodes update
18. PR merged
19. Sentry issue monitored
20. Evidence nodes created
21. Task becomes verified

This is the product.

⸻

14. Frontend architecture

For MVP, I would keep the UI simple and fast.

Screens

Inbox
Question Queue
Task / Work Packet View
Mini Graph View
Run / Handoff View
Verification View
Settings / Integrations

Frontend options

Given your likely speed with Elixir:

Option A: Phoenix LiveView

Good for MVP.

Pros:

fast iteration
real-time updates
less frontend complexity
easy background job progress updates

Cons:

less ideal for complex graph canvas later

Option B: React/TypeScript + Phoenix API

Better if you want a highly interactive graph UI early.

Pros:

better graph canvas ecosystem
easier rich client interactions

Cons:

more app complexity

My recommendation:

Phoenix backend + React/TypeScript frontend

Because the graph UI, inbox, and work packet editor will eventually benefit from a strong client. But a LiveView MVP is totally defensible if you want maximum speed.

⸻

15. Graph UI architecture

Do not make the graph the main UI at first.

Use the graph as the underlying model.

Render graph projections:

Tree projection

Goal
  Task
    Question
    Check

Queue projection

Questions blocking agent-ready tasks

Board projection

Needs answer | Ready for agent | In execution | Verified

Evidence projection

Task → Checks → Evidence

Dependency projection

Task A depends on Decision B and Check C

The MVP graph UI can be simple:

selected node in center
incoming edges on left
outgoing edges on right

Do not start with a giant Miro-style graph canvas. It will become visually impressive but not necessarily useful.

⸻

16. Context and retrieval architecture

For code-aware tasks, you need context retrieval.

MVP context sources

Sentry stack traces
GitHub issue text
PR diffs
CI logs
README/docs
File names and symbols
Recently changed files

Avoid full codebase embeddings at first unless needed.

Start with deterministic context:

stack trace file paths
PR changed files
test failure file names
Git blame/recent commits
linked issue references

Then add semantic retrieval later.

Possible context pipeline

External signal
→ extract file paths, symbols, stack frames
→ query GitHub for matching files/diffs
→ summarize relevant snippets
→ attach context artifacts
→ work packet compiler consumes them

For MVP, you can often get far with:

stack trace + recent PR diff + failing CI log + issue text

⸻

17. Agent policy model

Every executable task should have an autonomy policy.

{
  "allowed_actions": [
    "read_code",
    "modify_code",
    "run_tests",
    "open_pr"
  ],
  "forbidden_actions": [
    "modify_database_schema",
    "change_auth_policy",
    "edit_secrets",
    "deploy_to_production"
  ],
  "requires_approval_for": [
    "touching_payment_code",
    "changing_public_api",
    "modifying_migrations"
  ],
  "escalation": {
    "ask_if_confidence_below": 0.7,
    "ask_if_tests_missing": true
  }
}

Even if you are only exporting work packets initially, this policy should be included.

This becomes important later if you build real agent execution.

⸻

18. Trust architecture

You need trust features built in from the beginning.

Every AI-generated thing should have:

source
reason
confidence
created_by
timestamp
editable by human
supersession history

Example:

Question generated from:
- Sentry issue #4921
- Stack trace line 48
- Recent PR #812
Reason:
The correct invalid-state behavior is not specified.
Confidence:
0.84

This is not cosmetic. It is how users decide whether to trust the system.

⸻

19. Suggested MVP implementation phases

Phase 1: Manual/pasted intake

Before integrations are perfect.

Paste Sentry issue / GitHub issue / stack trace
→ generate work packet
→ question queue
→ readiness score

This lets you test the core behavior quickly.

⸻

Phase 2: GitHub integration

GitHub OAuth app
repo selection
issue import
PR sync
CI status sync

⸻

Phase 3: Sentry integration

Sentry OAuth / token
issue import
stack trace artifacts
event frequency
resolution status

⸻

Phase 4: Linear integration

create/update Linear issue
sync status
link task packet
comment with questions / decisions

⸻

Phase 5: CLI / local handoff

taskgraph pull TASK-123
taskgraph submit TASK-123

This makes the product useful even before full agent automation.

⸻

20. Later architecture: when it gets serious

Once the MVP works, the architecture can evolve.

Add an agent runner

Agent Orchestrator
  ↓
Sandbox manager
  ↓
Repo checkout
  ↓
Tool permissions
  ↓
Branch creation
  ↓
Test runner
  ↓
PR creator

Add plan-level execution

Plan node
  ├── Task A
  ├── Task B
  ├── Task C
  └── dependencies

Then:

parallel task scheduling
dependency-aware execution
human checkpoint gates
failure recovery

Add graph analytics

which decisions block the most work?
which tasks are agent-ready?
which repos generate the most unclear issues?
which agents succeed/fail most often?

Add learning

The system should learn team patterns:

preferred error handling style
test conventions
definition of done
which files are risky
which teams own what
common human decisions

This is where defensibility starts to show.

⸻

21. The actual core architecture in one sentence

A Postgres-backed typed work graph, fed by integration events, modified through validated AI-generated graph patches, projected into queues/work packets, handed off to humans or agents, and closed by evidence from GitHub, CI, Sentry, and human review.

That is the architecture.

The non-obvious part is this:

The product is not an agent. The product is the structured substrate that makes agent work safe, scoped, reviewable, and verifiable.

# Me
Do you think ash would be good to use?

# ChatGPT
Yes — Ash is a strong fit, with one caveat

For this product, Ash would be very good for the domain/business layer, especially because your app is fundamentally about typed resources, actions, policies, state transitions, and derived APIs.

I would not use Ash as a replacement for thinking carefully about the graph model. But I would strongly consider using Ash to model the core entities and workflows.

⸻

Why Ash fits this product

Ash’s core abstraction is modeling your application domain through resources and actions. That maps well to this product because almost everything in your system is a resource with constrained actions: tasks, questions, decisions, checks, work packets, runs, artifacts, external signals, and evidence.  

Ash actions are explicit ways to interact with resources — read, create, update, destroy, and generic actions — which is exactly what you want if AI is going to propose changes but not directly mutate truth.  

For example:

Task
  actions:
    create_from_signal
    mark_agent_ready
    assign_to_human
    assign_to_agent
    attach_evidence
    mark_verified
    archive

That is much cleaner than spreading business logic across random Ecto contexts, controllers, LiveViews, and background jobs.

⸻

Where Ash is especially useful

1. Typed domain model

Your resources could be:

Signal
Node
Edge
Task
Question
Decision
Check
Artifact
Evidence
WorkPacket
AgentRun
IntegrationEvent

Ash gives you a structured way to describe:

* attributes
* relationships
* actions
* validations
* policies
* calculations
* aggregates
* authorization
* API exposure

That matters because your product will become complicated fast.

⸻

2. Actions as “safe graph mutations”

This is probably the biggest reason to use Ash.

Instead of letting random code do:

Repo.insert!(%Node{})
Repo.insert!(%Edge{})
Repo.update!(task)

You define domain actions:

create_task_from_sentry_issue
answer_question
create_decision_from_answer
recalculate_agent_readiness
compile_work_packet
attach_pr_evidence
mark_task_verified

Then your LLM-generated GraphPatch can be validated and executed through those actions.

The architecture becomes:

LLM proposes GraphPatch
→ deterministic validator
→ Ash action
→ resource policies/validations
→ Postgres transaction
→ audit event

That is a good match.

⸻

3. Authorization and autonomy boundaries

Your product needs permissions at multiple levels:

Can this user answer this question?
Can this agent modify this task?
Can this run create a PR?
Can this agent touch auth/payment/schema-related nodes?
Can this integration create evidence?

Ash has built-in policy-oriented patterns for resource access, which is useful because authorization will not be a thin controller concern. It will be part of the domain model.

This matters a lot for agent safety.

⸻

4. Phoenix integration

Ash has ash_phoenix, which provides utilities for Phoenix forms, Phoenix LiveView, and related Phoenix integration.  

That is useful if you want to build the MVP quickly in Phoenix/LiveView:

Question Queue
Work Packet Editor
Task State Views
Integration Settings
Review/Approval Screens

Even if you eventually use React for the graph canvas, Ash + Phoenix is still a good backend combination.

⸻

5. Postgres support

AshPostgres is the PostgreSQL data layer for Ash, and the docs currently list PostgreSQL 13+ as the minimum supported version.  

For this app, that is important because I still think Postgres should be your initial source of truth:

nodes
edges
artifacts
external_events
graph_patches
work_packets
agent_runs
audit_events

You do not need Neo4j at MVP stage.

⸻

Where Ash may be awkward

1. The graph model itself

Ash is resource-oriented. Your graph is relationship-heavy.

That is fine, but you need to be careful not to force the entire graph abstraction into overly cute Ash resource relationships.

I would still have a fairly explicit graph schema:

nodes table
edges table
node_events table
artifacts table
node_artifacts table

Then wrap it in Ash resources/actions.

Do not try to model every possible node type as a separate table too early.

Better MVP shape:

Node resource
  type: :task | :question | :decision | :check | :signal | :artifact | :evidence
Edge resource
  type: :blocked_by | :answers | :validates | :generated_from | ...

Later, if some node types become very rich, you can split them into dedicated resources or extension tables.

⸻

2. You may fight the framework if the graph gets too dynamic

Your product has an inherently dynamic schema:

Different node types
Different edge types
Different properties
Different external integrations
Different agent policies

Ash likes declarative structure. That is mostly good, but too much dynamism can become awkward.

My recommendation:

Use Ash for stable domain operations, not for every experimental graph trick.

Good Ash resources:

Task
Question
Decision
AgentRun
WorkPacket
IntegrationEvent
Artifact

Generic graph layer:

Node
Edge
GraphPatch

Raw SQL/Ecto allowed for:

recursive graph traversal
deep dependency queries
bulk graph analytics
complex deduplication jobs

Do not be religious about Ash.

⸻

3. Learning curve and ecosystem risk

Ash is powerful, but it is not as universally known as plain Phoenix + Ecto.

That matters if:

* you need to hire quickly
* you want new contributors productive immediately
* you want maximum conventionality for a seed-stage codebase
* you expect investors/acquirers to scrutinize stack risk

That said, for you specifically, since you are already strong in Elixir, the productivity upside may outweigh the ecosystem risk.

⸻

How I would use Ash in this architecture

Use Ash for these

Core resources
Resource actions
Validation
Authorization
State transitions
Derived fields / calculations
Admin-ish APIs
Phoenix forms
Workflow actions

Use plain Ecto/SQL for these

Recursive graph traversal
Bulk graph operations
Graph analytics
Complex dedupe queries
Performance-critical ingestion
Event replay

Use Oban for these

Webhook processing
GraphPatch generation
Agent readiness scoring
Work packet compilation
Integration syncing
Verification polling

⸻

Concrete Ash resource sketch

Task

defmodule App.Work.Task do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer
  postgres do
    table "tasks"
    repo App.Repo
  end
  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :description, :string
    attribute :status, :atom do
      constraints one_of: [
        :draft,
        :needs_context,
        :needs_human_answer,
        :ready_for_agent,
        :in_execution,
        :needs_review,
        :monitoring,
        :verified,
        :archived
      ]
    end
    attribute :risk_level, :atom do
      constraints one_of: [:low, :medium, :high, :critical]
    end
    attribute :readiness_score, :integer
    attribute :success_criteria, {:array, :string}, default: []
    attribute :autonomy_policy, :map, default: %{}
  end
  actions do
    defaults [:read]
    create :create_from_signal do
      accept [:title, :description, :risk_level, :success_criteria]
    end
    update :mark_ready_for_agent do
      change set_attribute(:status, :ready_for_agent)
    end
    update :mark_verified do
      change set_attribute(:status, :verified)
    end
  end
end

⸻

Question

defmodule App.Work.Question do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer
  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :body, :string
    attribute :status, :atom do
      constraints one_of: [:open, :answered, :dismissed, :superseded]
    end
    attribute :why_it_matters, :string
    attribute :recommended_answer, :string
    attribute :source_confidence, :float
  end
  actions do
    defaults [:read, :create]
    update :answer do
      argument :answer_text, :string, allow_nil?: false
      change set_attribute(:status, :answered)
      # Could create Decision + graph edge in an after_action hook,
      # or better: call a domain service that runs a transaction.
    end
  end
end

⸻

The main design choice

You have two viable approaches.

Option A: Ash-first domain model

Task
Question
Decision
Check
Signal
Artifact
Evidence
AgentRun

Each is its own Ash resource.

Pros:

* clearer domain
* better validations
* better generated APIs/forms
* easier authorization
* more explicit actions

Cons:

* graph traversal across heterogeneous types is messier
* schema evolves more slowly
* dynamic node types become awkward

⸻

Option B: Graph-first model with Ash wrapping generic nodes

Node
Edge
Artifact
GraphPatch

Node.type determines whether something is a task, question, decision, etc.

Pros:

* flexible
* closer to actual graph model
* easier to add new node types
* better for AI-generated graph patches

Cons:

* weaker type safety
* more JSONB
* more validations pushed into app logic
* harder to expose polished forms/actions per type

⸻

My recommendation

Use a hybrid:

Generic graph substrate

Node
Edge
Artifact
NodeArtifact
GraphPatch
AuditEvent

Typed domain resources where behavior matters

Task
Question
Decision
Check
AgentRun
WorkPacket

In practice, this might mean:

nodes table stores canonical graph identity
tasks table extends node_id
questions table extends node_id
decisions table extends node_id
checks table extends node_id

Or, for MVP speed:

nodes table with type + properties JSONB
Ash resources/views/actions around specific node types

I would probably start with the second approach, then split tables later only when necessary.

⸻

Verdict

I would use Ash if:

* you are building in Elixir/Phoenix
* you want strong domain modeling
* you expect complex policies/actions
* you want explicit resource boundaries
* you want AI graph mutations to go through validated workflows
* you are okay with some framework complexity

I would avoid Ash if:

* you want maximum conventionality
* you expect to hire mostly non-Elixir developers soon
* you want a very custom graph engine from day one
* you want the backend to be mostly raw SQL + thin APIs
* you dislike DSL-heavy frameworks

For this specific product, I think Ash is a net positive.

The strongest version is:

Postgres as source of truth, Ash as the domain/action/policy layer, Oban as the job engine, and explicit GraphPatch validation between AI and the database.

That gives you the right balance: structured enough for safety, flexible enough for a graph-native AI product.