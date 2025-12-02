# Secret Santa with Exclusions

A privacy-focused Secret Santa web application where participants can secretly exclude people they don't want to be matched with.

## Features

- **No Login Required**: Token-based access for both admin and participants
- **Private Exclusions**: Each participant can exclude up to N people (configurable) without anyone else knowing
- **Solvability Check**: Algorithm checks if assignment is possible before running
- **Animated Reveal**: Fun slot-machine style animation when revealing your match
- **Mobile Friendly**: Responsive design works on all devices
- **Free Hosting**: Uses GitHub Pages + Supabase (both have generous free tiers)

## How It Works

1. **Creator** enters participant names and creates the group
2. **Creator** receives an admin link and individual links for each participant
3. **Participants** visit their unique link and select who they don't want to be matched with
4. **System** checks if a valid assignment is possible (considering all exclusions)
5. If solvable, **Creator** runs the assignment
6. **Participants** visit their link again to see an animated reveal of their match

## Tech Stack

- **Frontend**: Vanilla HTML/CSS/JavaScript (hosted on GitHub Pages)
- **Backend**: Supabase (free tier)
  - PostgreSQL database
  - Row-level security
  - Direct client access with SDK

## Deployment Guide

### Step 1: Set Up Supabase (5 minutes)

1. Go to [supabase.com](https://supabase.com) and create a free account
2. Create a new project (choose a region close to your users)
3. Wait for the project to initialize (~2 minutes)
4. Go to **SQL Editor** in the left sidebar
5. Copy the contents of `supabase/schema.sql` and run it
6. Go to **Settings** > **API** and copy:
   - Project URL (e.g., `https://xxxxx.supabase.co`)
   - `anon` public key (the long string)

### Step 2: Configure the App

1. Open `js/supabase-client.js`
2. Replace the placeholder values:

```javascript
const SUPABASE_URL = 'https://your-project.supabase.co';  // Your Project URL
const SUPABASE_ANON_KEY = 'your-anon-key-here';           // Your anon/public key
```

### Step 3: Deploy to GitHub Pages

1. Create a new repository on GitHub
2. Push this code to your repository:

```bash
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

3. Go to your repository **Settings** > **Pages**
4. Under "Source", select **main** branch and **/ (root)** folder
5. Click **Save**
6. Your site will be live at `https://YOUR_USERNAME.github.io/YOUR_REPO/`

### Alternative: Local Development

Just open `index.html` in a browser. For full functionality, you'll need the Supabase backend configured.

For local development with live reload:
```bash
npx serve .
```

## Project Structure

```
secret_santa_with_exclusions/
├── index.html              # Create group page
├── admin.html              # Admin dashboard
├── participant.html        # Participant page (exclusions + reveal)
├── css/
│   └── style.css           # All styles
├── js/
│   ├── supabase-client.js  # Database configuration & operations
│   └── algorithm.js        # Assignment algorithm
├── supabase/
│   └── schema.sql          # Database schema
└── README.md
```

## Algorithm

The assignment algorithm uses:
1. **Constraint Satisfaction**: Respects all exclusions (mutual blocking)
2. **Most Constrained First**: Assigns people with fewer options first for better success rate
3. **Randomization**: Shuffles valid options for random assignments
4. **Backtracking**: Tries different combinations if initial attempts fail

## Cost

**$0/month** for typical use:
- GitHub Pages: Free
- Supabase Free Tier:
  - 500 MB database
  - 50,000 monthly active users
  - Unlimited API requests

## Privacy Considerations

- Exclusions are stored in the database but only visible via participant's own token
- Admin cannot see who participants excluded (by design)
- No analytics or tracking
- All data stays in your Supabase project

## Customization

### Change Max Exclusions Default
Edit `index.html`, line ~25:
```html
<input type="number" id="maxExclusions" value="2" min="0" max="5">
```

### Change Colors
Edit `css/style.css`, the `:root` CSS variables at the top.

### Add Wishlists
You could extend the schema to include a `wishlist` text field in the `participants` table.

## Troubleshooting

### "Could not load group"
- Check that your Supabase URL and key are correct in `supabase-client.js`
- Ensure the database schema was run successfully
- Check browser console for detailed errors

### "Assignment not possible"
- Too many exclusions make it mathematically impossible
- Try reducing exclusions or adding more participants
- The algorithm needs at least one valid path for each person

### Links not working after deployment
- Make sure GitHub Pages is enabled
- Wait a few minutes for deployment
- Check that all files were committed and pushed

## License

MIT - Feel free to use and modify!
