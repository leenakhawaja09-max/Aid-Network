# Deploy Rapid Aid on Vercel (reliable method)

Vercel does **not** ship Flutter. Cloud builds often fail → white page + **404** on `flutter_bootstrap.js`.

This project deploys **pre-built** files from the **`vercel_static/`** folder (committed to git).

## One-time / before each web release

```powershell
cd CAN2.0\rapid_aid
.\tool\refresh_vercel_static.ps1
git add vercel_static vercel.json
git commit -m "Update web build for Vercel"
git push
```

Vercel will **Redeploy** automatically on push.

## Vercel dashboard — reset overrides (required if build log shows old echo text)

If the build log still says `Using committed Flutter web build` or `output is CAN2.0/rapid_aid/vercel_static`, the **dashboard is overriding git**. Fix:

1. **Project → Settings → Build and Deployment**
2. Turn **Override** **off** (or clear the text box) for **Install Command**, **Build Command**, and **Output Directory**
3. Save, then **Redeploy**

Pick **one** layout (do not mix):

### Option A — Repo root (recommended)

| Setting | Value |
|---------|--------|
| **Root Directory** | *(empty)* |
| **Output Directory** | *(empty — uses repo `vercel.json`)* |

Repo `vercel.json` copies `CAN2.0/rapid_aid/vercel_static` → `vercel_static` at deploy time.

### Option B — App subfolder

| Setting | Value |
|---------|--------|
| **Root Directory** | `CAN2.0/rapid_aid` |
| **Output Directory** | *(empty — uses `CAN2.0/rapid_aid/vercel.json`)* |

**Wrong:** Root Directory empty + Output `vercel_static` only → folder not at repo root → build error you saw.

**Do not** set Output to `web` or `build/web`.

## Verify after deploy

1. `https://YOUR-DOMAIN.vercel.app/flutter_bootstrap.js` → must **not** be 404
2. `https://YOUR-DOMAIN.vercel.app` → login screen (Ctrl+Shift+R)

## Supabase

**Authentication → URL Configuration**

- **Site URL:** `https://YOUR-DOMAIN.vercel.app`
- **Redirect URLs:** same URL

## Optional: build on Vercel (advanced)

Scripts `tool/vercel_install.sh` + `tool/vercel_build.sh` exist but are **not** used by default. Prefer `vercel_static/` + `refresh_vercel_static.ps1`.
