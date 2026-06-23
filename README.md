# StaticVision

> **See your fixer-upper potential before you buy.**  
> Upload a video walk-around and photos → AI reconstructs the floor plan → edit the blueprint → design the interior.

---

## Features

| Feature | Description |
|---|---|
| 📸 **Media upload** | Select photos (up to 10) and a video walk-around from your library |
| 🤖 **AI blueprint generation** | GPT-4o Vision analyses your photos and produces a scaled floor plan with room names & dimensions |
| ✏️ **Blueprint editor** | Drag rooms, resize them, add/delete rooms, rename them |
| 🛋️ **Interior design canvas** | Place furniture from a categorised palette, drag to position, delete items |
| 🎨 **Wall & floor styling** | Hex colour picker + colour presets, 6 floor materials |
| ✨ **AI design suggestions** | Ask GPT-4o for room-specific design ideas by style (modern, scandinavian, industrial, …) |
| 📐 **Style presets** | 6 curated full-room presets (Modern White, Warm Scandi, Industrial, Coastal Blue, Forest Cabin, Midnight Dark) |
| 🔐 **Auth** | Email/password sign-up and sign-in via Supabase Auth |
| ☁️ **Cloud storage** | Photos, videos and blueprints stored in Supabase Storage |

---

## Tech Stack

- **iOS 17+** · SwiftUI · async/await
- **Supabase** – Auth · PostgreSQL (PostgREST) · Storage
- **OpenAI GPT-4o** – Vision API for blueprint generation + design suggestions, accessed
  through a Supabase Edge Function so the API key stays server-side
- No third-party Swift packages required (raw URLSession calls)

---

## Project Structure

```
StaticVision/
├── StaticVision.xcodeproj/        Xcode project
├── StaticVision/
│   ├── StaticVisionApp.swift      App entry point
│   ├── ContentView.swift          Root auth gate
│   ├── Config/
│   │   └── AppConfig.swift        Supabase + OpenAI configuration
│   ├── Models/
│   │   ├── Project.swift          Project & ProjectMedia models
│   │   ├── Blueprint.swift        Blueprint, Room, FurnitureItem, FurnitureType
│   │   └── DesignElement.swift    AI response models, DesignPreset catalogue
│   ├── Services/
│   │   ├── SupabaseService.swift  Auth, database & storage REST wrapper
│   │   └── OpenAIService.swift    GPT-4o Vision calls & blueprint assembly
│   ├── ViewModels/
│   │   ├── AuthViewModel.swift
│   │   ├── ProjectViewModel.swift
│   │   ├── BlueprintViewModel.swift
│   │   └── DesignViewModel.swift
│   ├── Views/
│   │   ├── Auth/AuthView.swift
│   │   ├── Projects/{ProjectsView, NewProjectView, ProjectDetailView}.swift
│   │   ├── Blueprint/{BlueprintView, BlueprintEditorView}.swift
│   │   └── InteriorDesign/{InteriorDesignView, FurniturePaletteView}.swift
│   ├── Assets.xcassets/
│   ├── Info.plist
│   └── StaticVision.entitlements
└── supabase/
    ├── migrations/
    │   └── 20240101000000_initial_schema.sql
    └── functions/
        └── openai-proxy/        Edge Function that proxies OpenAI (keeps key server-side)
```

---

## Setup

### 1. Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. Run the migration in **SQL Editor** (paste the contents of `supabase/migrations/20240101000000_initial_schema.sql`).
3. Create two **Storage buckets** in the Supabase dashboard:
   - `project-media` – set to **private**
   - `blueprints` – set to **private**
4. Note your **Project URL** and **anon public key** from *Project Settings → API*.

### 2. OpenAI (server-side, via Supabase Edge Function)

The OpenAI key is **never** stored in the app — it lives server-side in the
`openai-proxy` Edge Function so it can't be extracted from the shipped binary.

1. Create an API key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
   and ensure your account has access to `gpt-4o`.
2. Deploy the proxy function and set the key as a Supabase secret:

   ```bash
   supabase functions deploy openai-proxy
   supabase secrets set OPENAI_API_KEY=sk-...
   ```

   The function authenticates callers with their Supabase session JWT, so only
   signed-in users of your app can use it.

### 3. Xcode – add your credentials

Open the scheme editor (**Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables**) and add:

| Variable | Value |
|---|---|
| `SUPABASE_URL` | `https://xxxx.supabase.co` |
| `SUPABASE_ANON_KEY` | `eyJ…` |

> **Never commit real keys.** The `Info.plist` reads from `$(VARIABLE_NAME)`, expanded at build time from the scheme environment or an `.xcconfig` file. The OpenAI key is not needed in the app.

Alternatively, create `StaticVision/Config.xcconfig` (add to `.gitignore`):

```xcconfig
SUPABASE_URL = https://xxxx.supabase.co
SUPABASE_ANON_KEY = eyJ…
```

Then reference it in the target's build settings.

### 4. Build & Run

```
open StaticVision.xcodeproj
```

Select your device/simulator and press **⌘R**.

---

## TestFlight / Distribution

### Option A – Codemagic CI (recommended, no Mac required)

This repo ships a [`codemagic.yaml`](codemagic.yaml) that builds the app and uploads it to
TestFlight automatically. One-time setup:

1. **Apple Developer Program** membership ($99/yr) and the bundle id `com.static-vision.app`
   registered (Codemagic can auto-create it on first build).
2. **App Store Connect API key** – create one in *App Store Connect → Users and Access →
   Integrations → App Store Connect API* (App Manager role), download the `.p8`, and add it
   in Codemagic under *Teams → Integrations → App Store Connect*. Name it
   `codemagic_asc_api_key` (or update the name in `codemagic.yaml`).
3. **Secrets group** – in Codemagic create an encrypted variable group `staticvision_secrets`
   with `SUPABASE_URL` and `SUPABASE_ANON_KEY`. The build injects these into `Info.plist`;
   they are never committed to git. (The OpenAI key is a Supabase secret, not a Codemagic one.)
4. Connect this GitHub repo to a Codemagic app and start the **`ios-testflight`** workflow.
5. In App Store Connect, add yourself as an **internal tester** – processed builds appear
   automatically in the TestFlight app.

### Option B – Xcode (manual archive)

1. In Xcode set your **Team** under *Signing & Capabilities* (needs an Apple Developer account).
2. The bundle identifier is `com.static-vision.app` – change it to match your developer account if needed.
3. Archive: **Product → Archive → Distribute App → TestFlight & App Store → Upload**.
4. In App Store Connect, add yourself as an **internal tester** and install via the TestFlight app.

Since this is an internal-only distribution you skip App Review entirely.

---

## Database Schema (summary)

```sql
projects       (id, user_id, name, description, status, media_count, blueprint_id, created_at, updated_at)
project_media  (id, project_id, media_type, storage_path, thumbnail_path, created_at)
blueprints     (id, project_id, rooms jsonb, scale, canvas_width, canvas_height, generated_at, updated_at)
```

All tables use Supabase Row-Level Security so users can only access their own data.

---

## How the AI pipeline works

1. User uploads photos (and optional video) of the property.
2. App extracts up to 6 representative photos.
3. Photos are sent to **GPT-4o** with a structured prompt asking for room names and estimated foot dimensions.
4. The JSON response is parsed into `Room` objects with auto-calculated canvas positions.
5. The blueprint is saved to Supabase and displayed on the interactive canvas.
6. User can regenerate at any time or edit rooms manually.

---

## Roadmap

- [ ] Video frame extraction (AVFoundation) for better blueprint accuracy
- [ ] Export blueprint as PDF / share sheet
- [ ] 3D preview using RealityKit
- [ ] Measurement overlays (tap two points → shows distance)
- [ ] Multiple blueprints per project (e.g. different layout options)
- [ ] Collaborative sharing (invite a co-buyer to view/edit)
