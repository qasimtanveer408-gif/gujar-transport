<<<<<<< HEAD
> **Latest release: archive / restore / permanent delete. Start with [START-HERE-ARCHIVE-DELETE.md](START-HERE-ARCHIVE-DELETE.md), including the new-database setup instructions.** The earlier release notes below remain as history.

=======
>>>>>>> 2aef45882bd9ec54781d025e3620f1f2677a5c83
# Gujjar Transport — ON karne ka tareeqa

1. Node.js **24.x** install karein.
2. ZIP extract karein aur **Gujjar-Transport** folder kholein. Isi folder mein `package.json` aur `START-WINDOWS.cmd` honge.
3. **START-WINDOWS.cmd** par double-click karein. Pehli dafa yeh dependencies install karega, phir website aur API start karega.
4. Browser mein **http://localhost:5173** kholein.
5. Apni existing admin email aur password se sign in karein.
6. CMD window khuli rakhein. Band karne ke liye terminal mein **Ctrl+C** dabayein.

Existing private `.env` configuration is package mein preserve hai. Data existing Supabase database mein save hota hai; website band karne se saved records delete nahi hote.

## Formula ka practical example

**Trips → Add trip** kholein. Vehicle aur driver select karein aur date/cycle number enter karein.

| Field | Value |
|---|---:|
| Fare | 80000 |
| Diesel | 29000 |
| Tolls | 3000 |
| Food | 1200 |
| Driver commission | 2000 |
| Other expenses | 800 |
| Start odometer | 144844 |
| End odometer | 145382 |
| Fuel litres | 68 |

Baqi expense fields zero rehne dein. Result typing ke saath update hoga:

- Total expenses: **36000.00 PKR**
- Profit: **44000.00 PKR**
- Distance: **538.000 km**
- Average: **7.91 km/L**

`Save changes` se draft save hoga. Record reopen karke values edit kar sakte hain. End odometer **145524** karne par distance **680 km** aur average **10.00 km/L** ho jayega.

Vehicle/driver summary ke totals approved completed trips se calculate hote hain. Trip ka **Complete → Submit → Approve** workflow complete karein. Overview ka **Fuel measurement basis** trip ke basis se match karein; default trip basis **Purchase estimate** hai. Minimum distance aur date filters bhi apply hote hain.

Calculated totals automatic hain. Data unke source fields, jaise fare, expenses, odometers aur fuel mein enter karein.

## Custom formula lagana

**Fields & print settings → Record module → Trips → Add custom field** se numeric inputs banayein, phir `Formula` type ka field banayein. Formula editor mein field keys insert karne ke buttons available hain.

Misal: do numeric fields `cf_quantity` aur `cf_rate` hon to formula `cf_quantity * cf_rate` use karein. Dusra formula `cf_total − 1.25` pehle calculated total ko use kar sakta hai. Formula results record save/reopen, cards, tables aur printouts mein automatically calculate hote hain.

## Agar start na ho

- Node ki version check karne ke liye CMD mein `node --version` run karein; project ko 24.x chahiye.
- Dependencies install karne ke liye project folder mein `npm.cmd ci` run karein.
- Configuration check: `npm.cmd run check:env`.
- Website start: `npm.cmd run dev`.
- Agar port 5000 ya 5173 occupied ho to pehli running project window band karke dobara start karein.

Detailed verification **FORMULA-REPAIR-VERIFICATION.md** mein hai. Current checks ke logs `verification/formula-repair-20261011/` mein hain. Purane verification folders historical evidence hain.
