# Gujjar Transport — Master Update

Existing project update ho gaya hai. Rebuild ya duplicate modules/database tables nahi banaye gaye. Audit `docs/MASTER_AUDIT.md` aur final results `docs/MASTER_UPDATE_TEST_REPORT.md` mein hain.

## Aap ke existing project ko update karna

1. Purane project folder aur database ka backup rakh lein. Apni working `.env` ko alag safe rakhein.
2. Updated ZIP ko **new folder** mein extract karein. Antigravity/VS Code mein andar wala `Gujjar-Transport` folder open karein, jahan `package.json` hai.
3. Apni existing `.env` isi folder mein copy karein. Same Supabase project, keys aur `SESSION_ENCRYPTION_KEY` rakhein. ZIP mein aap ki private `.env` shamil nahi thi; keys ko dobara generate karna zaroori nahi.
4. Agar pehle wali UI update ki migrations already apply hain, to apne **same Supabase project → SQL Editor → New query** mein is file ka complete SQL paste karke Run karein:

   `supabase/migrations/20261011160000_master_review.sql`

   Is migration se session expiry 3 hours hoti hai, existing driver Remarks save hotay hain aur two query indexes add hotay hain. Purane fleet/trip/loan records, user accounts aur transfer history delete nahi hotay. 3 hours se purani sessions sign-in dobara mangengi.

   Agar koi older migration apply nahi hui, pehle **sirf unapplied migrations** ko filename order mein apply karein. Purani applied SQL files dobara paste na karein. Database reset ki zaroorat nahi. CLI use karna ho to existing `npm.cmd run db:migrate` target confirmation ke saath pending migrations apply karta hai.

5. Purana dev server Ctrl+C se band karke, updated project ke PowerShell terminal mein:

```powershell
npm.cmd ci
npm.cmd run check:env
npm.cmd run dev
```

6. Browser mein `http://localhost:5173` kholein. Apna existing email/password use karein. Google login add nahi kiya gaya.

## Is update mein

- Session ka absolute time 12 se 3 hours. Dashboard ka existing periodic refresh alag setting hai aur wahi rehta hai. Token refresh session ko 3 hours se aage nahi barhata.
- Driver Remarks ka missing exact-form input aur database allowlist fix; same existing column use hota hai.
- Company/manufacturer, next-of-kin, Inam/reward aur driver cycle commission ke clear labels. Maintenance labels requested terms se match karte hain; same storage keys rehte hain.
- Buttons/icons/clickable cards/table rows par light CSS effects. Reduced-motion preference respected.
- Login par page code defer hota hai. Logo/favicon optimized; hashed assets cache hotay hain, private APIs cache nahi hoti. HTTPS Nginx examples mein gzip add hai.
- Input choices/dates validate hotay hain. Existing secure cookies, CSRF, role access, RLS, encrypted credentials, posting/reversal protection aur audit intact hain.
- Reference print structures, headers, tables, signatures aur PDF/XLSX routes retained; dense amount wrapping, component date widths, history headings aur HTML footer improve kiye hain.
- Meta title/description, robots.txt aur sitemap.xml available. Ye private staff/accounting app hai: crawler indexing blocked hai aur sitemap mein private records/routes nahi hain.

## Printed financial rules jo abhi confirmed nahi

Reference sheets ke shares/charity percentage, carried maintenance balances aur settlement deductions ki exact business rules supplied project mein configured nahi hain. Un cells mein guessed amounts nahi daale. Existing canonical revenue, expense, profit aur loan reports available hain; affected reference sheets par INCOMPLETE note rehta hai.

## Production

Same database aur credentials use karein. Node.js 24.x aur real HTTPS domain ke liye existing production environment guide/Nginx template follow karein. Server start se pehle pending migration apply karein.

```powershell
npm.cmd run build
npm.cmd start
```

Compiled build `dist` mein included hai. Hosted Supabase, aap ki hosting aur physical printer ko is workspace se test nahi kiya gaya.
