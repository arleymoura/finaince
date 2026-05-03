# finAInce Project Instructions

## Goal
This file defines persistent project guidance for work inside `finAInce`.
Use these instructions as the default project-specific behavior unless the user explicitly asks otherwise.

## Product Direction
- `finAInce` is not just an expense tracker. Treat it as a financial assistant product.
- Prefer features that turn existing financial data into practical help for the user.
- Prioritize usefulness in daily decision-making over adding passive metrics or generic dashboards.
- AI features must feel contextual, concrete, and actionable.

## Architecture
- Prefer small, isolated services for business logic.
- Keep SwiftUI views focused on rendering and interaction orchestration.
- Avoid embedding heavy computation directly inside `body` or computed properties used by `body`.
- Expensive calculations should run through cached state, explicit refresh methods, `.task`, `onAppear`, or dedicated services.
- Reuse existing service boundaries when reasonable:
  - `InsightEngine` for insight generation
  - `SavingsOpportunityService` for savings opportunities
  - dedicated services for import, receipt extraction, categorization, and draft resolution
- When introducing a new cross-cutting behavior, prefer a new service instead of growing an unrelated one.

## AI Features
- AI should not be used as a substitute for deterministic detection logic.
- First detect signals with deterministic product logic.
- Then use AI to explain, deepen, or operationalize the result.
- Every AI-facing feature should answer:
  - what was detected
  - why it matters
  - what the user can do now
- Avoid generic prompts and generic outputs.
- Provide rich prompts with concrete financial context whenever possible.
- AI features should have a reasonable deterministic fallback when the product depends on them.

## Opportunities
- A savings opportunity is valid only if all three are present:
  - concrete savings amount
  - clear source of savings
  - actionable user behavior to capture that savings
- If one of those is missing, do not treat it as a real opportunity.
- Prefer the most specific category level available for opportunity analysis.
- For opportunities, prioritize subcategory over root category when data exists.
- Use merchant repetition and transaction frequency when available to make recommendations more concrete.

## Insights
- Insights and opportunities may share visual structure, but they are not the same conceptually.
- When unifying cards or carousels, preserve the source type clearly in the badge/title treatment.
- Badge text should reflect the real content type, for example:
  - `Insight`
  - `Oportunidade`

## Performance
- Avoid introducing structural slowdowns.
- Do not run heavy engines repeatedly during navigation transitions.
- Never place heavy calculations inside render paths if they can be avoided.
- Prefer explicit loading states over synchronous work that blocks screen presentation.
- If a feature needs async loading in a view, give it independent loading state.

## SwiftUI / UI
- Preserve the app’s established visual language unless the user requests a redesign.
- Reuse existing card structures and components when possible before creating new visual patterns.
- Keep empty states useful, not decorative.
- Empty states should guide the user toward meaningful actions.
- Loading states should be lightweight and proportional to the section they represent.
- Avoid oversized cards when the same information can be expressed more compactly.
- For horizontally scrolling action cards, keep copy concise and scan-friendly.

## Localization
- Every user-facing string must be localized through `Strings.swift`.
- Whenever adding a new string, update all supported languages currently used by the project:
  - Portuguese
  - English
  - Spanish
- Do not leave hardcoded PT-BR copy in services, notifications, or view logic.

## Debugging and Mocks
- Temporary mocks are allowed for UI validation when real data is unavailable.
- Mocks must be clearly identifiable in code and easy to remove.
- Remove temporary mocks after the user finishes validating the UI unless the user asks to keep them.
- Debug prints are acceptable in deterministic engines during investigation, but should remain scoped and intentional.
- Prefer `#if DEBUG` for diagnostic-only logging.

## Dashboard Rules
- Dashboard cards should be informative, concise, and actionable.
- If the dashboard carousel combines multiple signal types, the card structure should remain consistent:
  - badge
  - title
  - descriptive text
  - call to action
- Avoid adding a separate dashboard widget if the same concept already belongs in an existing carousel or section.

## Chat Rules
- The chat empty state should function as an AI hub, not only a blank conversation prompt.
- Prefer actionable modules such as:
  - insights
  - opportunities
  - analysis entry points
  - education with context
- Keep loading for each AI section independent when practical.

## Editing Rules
- Prefer focused changes over broad refactors unless the user asks for broader cleanup.
- Do not remove or revert user work unless explicitly requested.
- Use temporary scaffolding only when it helps validate UI or behavior and then remove it promptly.

## Validation
- After relevant code changes:
  - refresh diagnostics for edited files
  - run a project build when the change affects app behavior or compilation across files
- If warnings remain and are unrelated to the requested work, mention that clearly.

## Preferred Collaboration Style
- Be direct.
- Be concise.
- Explain product or technical tradeoffs clearly when they matter.
- When a feature request implies a product rule, make that rule explicit in implementation decisions.
