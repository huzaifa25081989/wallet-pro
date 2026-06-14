# Wallet Pro 💰

Your own 100% free, lifetime, no-ads personal finance app — built like Wallet by BudgetBakers.

**Features:** Accounts & wallets (Bank / Cash / Savings / Investment / Credit) · Income, expense & transfer records · Search & filters · Reports (pie + 6-month bar charts, weekly/monthly/yearly) · Net worth · Chart of Accounts (Assets / Liabilities / Equity / Income / Expenses) · Loans & debts with repayment progress · Monthly budgets with color-coded progress · Voice entry ("expense 500 groceries") · Import your data from Wallet (BudgetBakers) · Local + Google Drive backup with daily auto-backup.

All data stays on your phone. Currency is set to **Rs** (change `kCur` in `lib/widgets.dart` if you ever want a different symbol).

---

## Part 1 — Build the APK (one-time, ~15 minutes, no software to install)

GitHub builds the app for you in the cloud, free.

1. Go to **github.com** and sign in (create a free account if needed).
2. Click **+ → New repository**. Name it `wallet-pro`, set it to **Private**, click **Create repository**.
3. On the new repo page click **uploading an existing file** (or **Add file → Upload files**).
4. On your computer, unzip `wallet_pro_source.zip`, then **drag ALL the contents of the folder** (the `lib`, `signing`, and `.github` folders plus `pubspec.yaml` and `README.md`) into the GitHub upload box.
   - ⚠️ The `.github` folder is hidden on some computers. On Windows: File Explorer → View → tick **Hidden items**. On Mac: press **Cmd+Shift+.** in Finder.
   - If you can't upload `.github`, do this instead: in the repo click **Add file → Create new file**, type the filename `.github/workflows/build-apk.yml` (the slashes create the folders), then copy-paste the contents of that file from the zip and click **Commit**.
5. Click **Commit changes**. The build starts automatically.
6. Click the **Actions** tab → click the running **Build Wallet Pro APK** workflow → wait ~5–8 minutes until it shows a green ✔.
7. On the finished run's page, scroll to **Artifacts** and download **WalletPro-APK** (a zip containing `app-release.apk`).

## Part 2 — Install on your phone

1. Send `app-release.apk` to your phone (WhatsApp "message yourself", email, USB cable, or Google Drive).
2. Tap the file on your phone. Android will ask to allow installs from that app → **Allow / Settings → Allow from this source**.
3. Tap **Install**. Done — Wallet Pro appears in your app drawer.

**Updating later:** edit any file in the GitHub repo (or just re-run the workflow from the Actions tab), download the new APK, and install over the old one — your data is kept, because the app is always signed with the same key (`signing/debug.keystore`).

## Part 3 — Bring your data from Wallet (BudgetBakers)

1. In the **Wallet** app: **More → Export → CSV** (or on web: budgetbakers.com → Export). Choose all accounts and the full date range.
2. Send the CSV file to your phone if it isn't already there.
3. In **Wallet Pro**: **More → Import from Wallet (BudgetBakers)** → pick the CSV.
4. Accounts and categories are created automatically; all records are imported.
   - Note: Wallet exports transfers as two rows (money out + money in). They're imported that way, so all account balances remain correct.
5. After importing, open each account (Home → tap account → ✏️) and set its correct **type** and **opening balance** if needed.

## Part 4 — Google Drive backup (optional, one-time setup)

The "Export backup file" option works immediately with no setup. For the built-in **Google Drive** backup (and daily auto-backup) Google requires you to register the app once — free, ~10 minutes:

1. Go to **console.cloud.google.com** and sign in with your Gmail.
2. Top bar → **Select a project → New Project** → name it `wallet-pro` → Create.
3. Menu → **APIs & Services → Library** → search **Google Drive API** → **Enable**.
4. Menu → **APIs & Services → OAuth consent screen**:
   - User type: **External** → Create.
   - App name: `Wallet Pro`, your email in both email fields → Save through all steps.
   - Under **Audience / Test users** click **+ Add users** and add **your own Gmail address**.
5. Menu → **APIs & Services → Credentials → + Create credentials → OAuth client ID**:
   - Application type: **Android**
   - Package name: `com.huzaifa.wallet_pro`
   - SHA-1 certificate fingerprint:
     ```
     E0:65:41:60:17:12:AC:CC:F2:79:71:B8:62:93:E7:BE:37:F2:32:A5
     ```
   - Click **Create**.
6. Wait 5–10 minutes, then in Wallet Pro: **More → Back up to Google Drive now** → sign in with your Gmail → done. Turn on **Auto backup daily** if you want it automatic.

Backups are stored in your Drive's hidden app-data area (they don't clutter your Drive, and only Wallet Pro can read them). To move to a new phone: install the APK, set up nothing, just tap **Restore from Google Drive**.

## Troubleshooting

- **Build fails in Actions:** open the failed step's log. Most common fix: re-run the job (Actions → failed run → **Re-run all jobs**) — occasional network hiccups happen.
- **"App not installed":** an older differently-signed copy exists — uninstall it first, then install.
- **Drive sign-in fails:** the OAuth client's package name or SHA-1 doesn't match (copy them exactly from above), or your Gmail isn't added as a **test user** on the consent screen.
- **Voice button does nothing:** allow the microphone permission when asked, and make sure the Google app / speech services are enabled on the phone.

## Project structure

```
pubspec.yaml                     dependencies
.github/workflows/build-apk.yml  cloud build recipe
signing/debug.keystore           stable signing key (keep it — never delete)
lib/
  main.dart                      app shell + tabs
  db.dart                        SQLite database
  widgets.dart                   shared helpers
  screens/                       all screens
```
