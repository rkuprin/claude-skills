# The Personal Harness

*A working thesis on how knowledge work reorganizes when everyone can build their own
machinery around a model — and why a shared or imposed harness misses the point.*

## The old constraint

Ten years ago, starting a project meant asking: do I have the energy, the time, the
internal resources to finish it? The binding constraint was personal, and it was
different for everyone.

A concrete example. While looking for a flat, I caught myself re-reading the same real
estate listings over and over. The attention spent re-scanning listings I had already
seen cost more than building a small Chrome extension that hid what I had already
viewed. So I built it. For me, the scarce resource was **focus**. For someone else it
is memory, or stamina, or something else entirely. The point is not the extension —
it is that the bottleneck was *mine*, specific to my wiring, and the fix was shaped to
it.

## Choice used to be a patchwork of preferences and impositions

We all assembled our way of acting in the world from two sources:

- **Preference.** You choose Instagram or not, VS Code or not, your own standards,
  your own toolbox. This layer is personal by definition.
- **Imposition.** Some conditions are forced on you by where you work or what your
  body is. A friend of mine has ADHD and serves actively in the US Marine Corps. I
  have ADHD too — and I take medication, while she cannot, because she is in active
  service. Her entire way of organizing life revolves around a constraint she did not
  choose. Her toolbox is different from mine not because of taste but because of her
  conditions.

So even before any technology enters the picture, each person's way of operating is
already a *custom harness*: an improvisation around personal strengths, personal
deficits, and personal circumstances.

## Then SaaS flattened everyone into the same shape

The last decade of software went the other way. Everyone used the same platforms, the
same dashboards, the same workflows. The tooling was designed for an average user who
does not exist, and each of us paid the difference privately — the doctor working
around the hospital system, the analyst exporting to Excel because the real tool
couldn't, anyone who ever muttered "this software wasn't built for how I think."

That era is ending, and the reason is specific: **code can now be produced in
quantities that were incomprehensible before.** The cost of building a small,
personal, single-purpose tool has collapsed to nearly zero. The Chrome extension that
was worth building for a flat hunt is now worth building for a task you'll do twice.

## The thesis: everyone will build their own harness

A model — an LLM — is a general capability with no shape. To act in the world it
needs a harness: the workflows, tools, memory, and rules wrapped around it. The claim
of this note is simple:

> Each person will build their own harness around model capability — shaped to their
> own strengths, habits, deficits, and responsibilities. A harness you did not build,
> one imposed by an employer or inherited from a platform, is a misunderstanding of
> where this is going. It repeats the SaaS mistake one level up.

The strongest argument is a profession that is not software at all. Consider a family
doctor. A GP's talent is not memory — it is the ability to see the person behind the
information. A patient walks in; the doctor glances at a screen showing the last
visits, the specialist referral, the blood test — and then looks up and sees the
face: how tired this person is, what is actually bothering them. The doctor's task is
a decisive, executable judgment, delivered across a table as support for a life.

Different doctors have different **points of control** over that encounter. One reads
the numbers first, another reads the face first, a third watches what the patient
avoids saying. There is no one-stop-shop system that serves all of them, because the
valuable part of each doctor is precisely the part that differs. What each of them
benefits from is a harness that *exposes what they personally care about* — their own
vital signs, in their own order — and stays out of the way of the judgment only they
can make. That harness cannot be issued centrally. It has to be built by, or at least
with, the person who carries the responsibility.

## What a harness is made of: a living example

I run one such harness now, for software work, built around several models and
myself. It is a real, daily-use system, and its structure illustrates what personal
harnesses will converge on — because it turned out to be shaped less by technology
than by **accountability**.

The chain of consequence matters: if the work fails, I bear it. I am the stakeholder
who risks something. That single fact organizes the whole delegation structure into
three layers with three different characters:

1. **A management layer.** An orchestrator that plans, routes, and decides. It holds
   real executive authority — it is expected to have a bold opinion about what,
   when, and in which order. It consults me at the seams where consequences land on
   me: approving the plan, vetoing a dispatch, confirming a takeover. Everywhere
   else, it decides. A manager squeezed into too-tight rules cannot manage; its
   charter is written in judgment-grade prose, not procedure.
2. **An execution layer.** Precise, technical, concrete — because in the end we are
   building software, and software is unforgiving. Precision is stratified by layer:
   the manager judges, the executor compiles.
3. **A critic layer.** A *different persona* — in practice, a different model family
   — whose loyalty is to being right, not to any role. It treats the plan as a claim
   to test, questions the premise before the execution, and sees everything: its
   value depends on completeness of information and on not sharing the executor's
   blind spots. Its advice is weighed, never automatically enforced — but no plan is
   finished until the critic has read it and spoken.

Two design convictions hold the system together, and both generalize:

- **No mind is trusted with state or memory.** What must be true lives in durable,
  inspectable artifacts (in my case: git history and an append-only event log), never
  in anyone's recollection — human or model. Minds are for judgment; furniture is
  for memory.
- **Sessions are disposable; the harness carries continuity.** Any single working
  session — mine or a model's — is treated as cheap and sheddable. The system is
  designed so a fresh participant can pick up the work from the artifacts alone.

Note what is absent: there is no fourth role. Decide, do, check, remember — and the
fourth function was deliberately *not* given to a mind. Every additional mind is
another state-sharing problem; the architecture works because it minimizes exactly
that.

## Why this is not a software story

The three layers — management, execution, critic — are not a software methodology.
They are what any accountable delegation looks like once the executive function can be
staffed cheaply. The family doctor's harness will have the same shape: something that
assembles the situation (management of attention), something that carries out the
concrete acts (ordering tests, writing referrals — execution), and something that
argues (a differential-diagnosis adversary that asks "what if you are wrong?" before
the decision lands). The doctor still carries the responsibility and still makes the
call across the table. The harness does not replace the doctor's judgment; it
protects it from everything that is not judgment.

The same will hold for a teacher, a lawyer, a researcher. Each will assemble a
harness around their own points of control, their own deficits, their own chain of
accountability. The harnesses will rhyme — three layers, artifact memory, disposable
sessions — but they will not be identical, because the people are not identical.

## The question I want to put to you

If this is right, then "which AI tool does your organization use?" is the wrong
question — as wrong as asking which brand of glasses everyone should share. The right
questions are personal: Where is *your* bottleneck? What does *your* screen need to
show first? Who bears the consequences of *your* decisions, and how does your harness
bring them to you at exactly the moments where you must decide?

I would especially value a challenge to the strong version of the claim: that an
imposed or shared harness is not merely inconvenient but a category error — an attempt
to standardize the one layer of the stack that is irreducibly personal. Is there a
case where the shared harness is the right answer? And what happens to institutions —
hospitals, universities, armies — that are built on imposing one?
