# Circles UX + Realtime Global Rankings

**Goal:** Make Circles social, reliable, and shareable. Add a true server-authoritative global leaderboard.

**Backend (Cloudflare Worker + Durable Object)**
- Single `Hub` DO with SQLite tables: `users`, `circles`, `circle_members`.
- Endpoints:
  - `POST /users/upsert` — name, xp, streak, tier, avatar seed.
  - `GET /rankings/global?userId=…` — top 100 + my row + total users.
  - `POST /circles` — create.
  - `POST /circles/join` — join by code.
  - `GET /circles?userId=…` — my circles + ranked members.
  - `GET /circles/:id?userId=…` — one circle.
  - `POST /circles/:id/leave`, `DELETE /circles/:id`.
  - `GET /.well-known/apple-app-site-association` — universal links AASA.
  - `GET /join/:code` — friendly landing page (also handled as universal link by app).

**Swift**
- `BackendService` wraps backend, identified by Apple user ID (or generated UUID as fallback).
- Auto‑sync user profile (name, xp, streak, tier) on launch and whenever XP changes.
- `CirclesView` pulls from backend (with SwiftData as offline cache) + 5s polling when visible.
- `GroupDetailView` lists real ranked members from backend.
- New `GlobalRankingsView` — Top 100, current user always shown, highlighted row, smooth refresh.
- Invite codes: prominent in card + large tap‑to‑copy on detail header + native `ShareLink` everywhere.
- Universal links via `applinks:` entitlement + AASA — tapping `https://…/join/CODE` opens app with code prefilled in join sheet.
- Custom URL scheme `ascend://join/CODE` as deep‑link fallback.

**Apple Review**
- Real backend persistence so circles work across devices.
- Universal links require the matching AASA file served at the worker root.
