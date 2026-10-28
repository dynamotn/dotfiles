---
name: learn
description: Use when the user wants to learn a skill or subject, prepare for an exam or certification, plan a study schedule, asks why they keep forgetting what they studied or how to study better, or types /learn - picks one to three evidence-based learning methods for the goal and time frame and turns them into a concrete plan.
---

# Learn

Turn "I want to learn X" into a plan built from methods with good evidence
behind them, sized to the goal, the deadline and the time the user really
has. Inspired by the routing idea of
[ironyjk/learning-framework](https://github.com/ironyjk/learning-framework)
(CC BY-NC 4.0), rewritten for this machine; no text is copied from it.

## The one principle

Learning that feels easy is usually learning that does not last. Rereading,
highlighting and reading summaries feel productive and do little; testing
yourself, spacing reviews and mixing problem types feel slow and work
(Bjork's *desirable difficulties*). Say so when the user's plan leans on the
easy kind, and never pick a method only because it is comfortable.

Evidence ranking (Dunlosky et al., 2013, *Psychological Science in the
Public Interest*): practice testing and distributed practice are high
utility; elaborative interrogation, self-explanation and interleaving are
moderate; summarizing, highlighting, the keyword mnemonic, imagery and
rereading are low. Learning styles (VAK), left/right brain, speed reading
and the "10,000-hour rule" are not methods; correct them when they come up.

## 1. Ask only what changes the plan

Infer what you can from the request and ask in one message for the rest:

- **Goal:** pass an exam (format and date), gain a usable skill, build
  understanding of a field, or fix focus.
- **Time frame:** under two weeks, one to three months, three to twelve
  months, or open-ended.
- **Time per day and its shape:** long blocks, or scattered minutes on a
  phone.
- **What already failed**, if they tried before.

## 2. Pick one to three methods

| Goal | Core | Add when |
|---|---|---|
| Exam or certification | retrieval practice + spaced repetition | interleaving from one month out; past-paper analysis (metalearning) from three months out |
| Usable skill (language, coding, music) | deliberate practice + direct practice on the real task | feedback loop from a person or a tool; ultralearning for an intense project |
| Understanding a field | Feynman technique (explain it plainly) + permanent notes in the user's own words | spaced repetition for the terms; chunking via worked examples first |
| Long-term knowledge | permanent notes linked to each other | progressive summarization only as a reading aid, never as the learning |
| Focus | deep-work blocks or Pomodoro to start | attention-residue habits: one task per block, a shutdown note |

A beginner gets one or two, not five. When two methods pull against each
other (cramming for a date versus spacing for retention), name the trade-off
and let the user choose.

## 3. Use the user's own system

The user keeps an Obsidian vault reached through the `dybrain` MCP server.
When it is connected:

- `lookup` or `search` the methods you picked (`Luyện truy xuất`,
  `Lặp lại ngắt quãng`, `Học xen kẽ`, `Khó khăn đáng có`, `Gom khối (tâm
  lý học)`, `Siêu học tập`, `Ultralearning`, `Luyện tập có chủ đích`,
  `Kỹ thuật Feynman`, `Làm việc sâu`) and link the pages rather than
  re-explaining them at length.
- Cards go into the Spaced Repetition plugin: a note tagged
  `flashcards/<subject>/<deck>` with cards in a `## Flashcards` section.
  The English and Chinese tracks already have their hubs (`English`,
  `Chinese`) and decks; build on them instead of starting a parallel one.
- A plan worth keeping becomes a project note (`create_note`, kind
  `project`) with falsifiable done criteria, such as "IELTS listening 6.5 on
  two full mock tests" rather than "better listening".
- Never read `ai: sensitive` notes, past daily notes included, to judge
  progress; ask the user instead.

Without the server, give the plan in the reply.

## 4. The plan

Write it short and concrete:

- the methods chosen, one line each on why they fit this goal;
- a weekly rhythm that fits the stated time (session length, what each
  session does, when reviews happen);
- the first session, step by step, so the user can start today;
- how progress is measured (a mock test, a recorded attempt, a cold recall
  of last week's material), and when to revisit the plan;
- what to stop doing, if the current habit is a low-utility one.

## Boundaries

Medical, legal and licensing exams may need strategies beyond this skill;
say so. Children's education, therapy and team learning are out of scope.
