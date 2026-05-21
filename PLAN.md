# Replace Coach tab with an iMessage-style AI chat that can act inside the app

## What changes

The Coach tab will no longer show summary/focus/action cards. Instead it becomes a clean, iMessage-style chat where you talk with your AI coach and it can actually do things in the app for you.

## Features

- **Conversational coach**: Ask anything — "why did my PSL drop?", "give me a 4-week cut plan", "how am I doing this week?" — and get short, specific replies grounded in your real data (scans, meals, lifts, streak, hydration).
- **Attach photos**: Send a meal pic, progress photo, or selfie right in the chat. The AI analyzes it and replies with feedback or logs it for you.
- **AI can take actions for you** (you'll see each action as a small card inside the conversation):
  - Lower or raise calorie & protein targets ("I was sick, drop my cals for the next 3 days")
  - Update profile (weight, height, age, goals, metric/imperial units)
  - Log or remove meals
  - Log bench / squat / deadlift PRs
  - Log water glasses
  - Open the Cal AI, Physique, or PSL scan flow with one tap
  - Generate a personalized weekly plan from your latest data
- **Smart confirmation**:
  - Small actions (hydration, single meal log) apply instantly with a tiny "Undo" pill.
  - Big actions (changing your calorie target, weight, goals, profile) show a confirm card with **Apply** / **Cancel** before anything changes.
- **Suggested prompts**: A row of tappable starter chips above the input ("Adjust today's cals — I was sick", "Plan my week", "Log 200g chicken & rice", "How's my progress?", "Log bench PR"). Tapping fills the input.
- **Privacy guard**: The AI is told what it can and cannot access — it will never reveal raw private data like your Apple ID, email, internal IDs, or other users' info. It only summarizes your own stats.
- **Fallbacks**: If the primary model fails, it auto-tries backup models (same chain Cal AI uses). If everything fails, you still get a friendly offline reply with a deterministic plan from your local stats — chat never feels broken.
- **Privacy of conversation**: Messages live only in memory for the current session. Closing and re-opening the app starts a fresh chat (no chat history persisted to disk).

## Design

- **Top bar**: Small "Coach" title, sparkle icon, a "New chat" button on the right that clears the conversation with a soft fade.
- **Bubbles**:
  - Your messages: right-aligned, accent-tinted glass bubble, tight rounded corners.
  - AI messages: left-aligned, neutral glass bubble with subtle border, with a tiny sparkle avatar.
  - Photo attachments render as rounded thumbnails inside the bubble.
- **Action cards**: Inline, slightly different look from a normal bubble — a glass card with an icon (fork, dumbbell, drop, scale, target), a one-line description ("Lower calorie target to 2,200 cal/day for 3 days"), and either an instant "Applied · Undo" pill or **Apply** / **Cancel** buttons for confirmation.
- **Typing indicator**: Three softly pulsing dots in an AI bubble while the model is thinking.
- **Suggested prompts**: Horizontally scrolling chips with subtle border, shown above the input when the chat is empty or after the last AI message.
- **Composer**: Rounded pill input, paperclip button on the left for photos, send arrow on the right that glows when text is present. Haptic tap on send.
- **Empty state**: Centered sparkle, "Your AI coach", one line explaining what it can do, suggested prompts below.
- **Motion**: New bubbles spring in from the bottom; action cards fade-up; "Applied" pill flashes green briefly.

## Screens

- **Coach tab (replaces current AI Analysis screen)**: The chat itself — message list, suggested prompts, composer, attachment picker sheet.
- **Confirm sheet** (inline card, not a separate screen): Appears within the chat flow when AI proposes a big change; shows the exact field, old value → new value, with Apply / Cancel.

## Safety & reliability

- AI requests still go through the existing consent gate (no behavior change there).
- Tool-style action calls are validated on-device (e.g. weight must be in a sane range, calorie target capped, units must be metric/imperial) so the AI can't accidentally corrupt your profile.
- The AI is explicitly instructed never to expose private fields, tokens, Apple ID, or anything beyond your own visible app data.