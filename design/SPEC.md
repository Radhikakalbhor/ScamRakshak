# ScamRakshak — Home Screen UI Specification

Content, labels, hierarchy and order of the home screen. Visual style: `design/DESIGN_SYSTEM.md`.

## Numbered elements (in order)
1. **App logo and company name** — shield logo at the top-left, "ScamRakshak" beside it. Brand teal as accent.
2. **Language / भाषा** — compact selector below the header with EN · हिन्दी · छत्तीसगढ़ी; selected language clearly marked.
3. **Notification** — bell at the top-right of the header.
4. **Report Fraud** — the most prominent element, full-width, alert red. Phone action **1930**.
   Supporting text: "Register incident & alert community". Arrow: opens the reporting flow.
5. **Check Message** — "Detect SMS & WhatsApp fraud", message icon, arrow. First row of the grid.
6. **Check QR Code** — "Spot fake payment QR codes", QR icon, arrow. Beside Check Message.
7. **Check Call** — "Analyze suspicious call transcripts", phone icon, arrow. Next grid row.
   - **Live Call Guard** — "Microphone + speakerphone; may not work on all phones", audio icon, arrow. Beside Check Call.
8. **Digital Financial Literacy Score** — score prominent (0 /100 initially), "From your quiz answers and
   the lessons you finished. Stays on this phone.", horizontal progress bar, "Read a lesson or take the
   quiz to get your score.", "Next: read the lesson "Keep your OTP secret".", buttons **Open lessons**
   and **Take a quiz** (stacked).

After the spec'd sections the existing **Scam Trends** entry (District-level cybercrime data) is kept so
no existing home functionality is lost.

## Copy (exact)
ScamRakshak · Language / भाषा · EN · हिन्दी · छत्तीसगढ़ी · Report Fraud · 1930 · Register incident & alert
community · Check Message · Detect SMS & WhatsApp fraud · Check QR Code · Spot fake payment QR codes ·
Check Call · Analyze suspicious call transcripts · Live Call Guard · Digital Financial Literacy Score ·
From your quiz answers and the lessons you finished. Stays on this phone. · Read a lesson or take the
quiz to get your score. · Next: read the lesson "Keep your OTP secret". · Open lessons · Take a quiz

## Notes
- Header greeting ("Offline Protected") and title ("Stay safe from fraud") follow the reference style's
  greeting + large heading pattern; they are translated in en/hi/chh.
- The bell opens Recording Alerts (`/live/inbox`), the app's notification history.
