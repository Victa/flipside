# Milestone 4.5 Testing Checklist - Task 23g

**Date:** February 14, 2026  
**Objective:** Comprehensive testing of post-scan flow refactor (carousel and DetailView)

## Test Environment Setup

- **Device:** iPhone 17 Pro Simulator (iOS 17.0+)
- **API Keys Required:** 
  - OpenAI API key (configured in Settings)
  - Discogs Personal Access Token (configured in Settings)
- **Test Images:** Have several vinyl record images ready (covers, labels, clear/blurry)

---

## ✅ Test Scenario 1: New Scan - Happy Path

### Steps:
1. Launch app
2. Tap FAB (floating action button) in bottom-right
3. Select "Choose from Library" or "Take Photo"
4. Select/capture a clear vinyl record image
5. Wait for ProcessingView to complete
6. Observe ResultView with horizontal carousel

### Expected Results:
- [ ] ProcessingView shows loading animation
- [ ] ResultView displays with horizontal carousel of matches
- [ ] Carousel shows 3-5 match cards (if matches found)
- [ ] Scanned image visible at top of ResultView
- [ ] Match cards show: artwork, title, artist, year, label, confidence score
- [ ] Cards are horizontally scrollable with smooth animation
- [ ] Tap a match card → navigates to DetailView
- [ ] DetailView shows: large artwork, full metadata, track listing, "View on Discogs" button
- [ ] "View on Discogs" button opens Safari with correct URL
- [ ] Back button returns to carousel (ResultView)
- [ ] Select different match → updates DetailView correctly

### Pass Criteria:
✅ All navigation flows work smoothly  
✅ No crashes or layout issues  
✅ Scan is saved to HistoryView

---

## ✅ Test Scenario 2: Reopening Saved Scans

### Setup:
Complete Test Scenario 1 first (create at least 2 saved scans, one with selected match, one without)

### Steps:
1. From HistoryView, tap a scan that has NO selected match yet
2. Observe navigation
3. Go back to HistoryView
4. Tap a scan where you previously selected a match
5. Observe navigation

### Expected Results:
- [ ] Scan with no selection → opens ResultView (carousel)
- [ ] Scan with selected match → opens DetailView directly
- [ ] No unnecessary network calls (data loaded from cache)
- [ ] Offline mode: can browse saved scans with airplane mode enabled
- [ ] All saved images and metadata display correctly

### Pass Criteria:
✅ Direct navigation to DetailView when match was previously selected  
✅ Carousel navigation when no match selected  
✅ Offline viewing works (test with airplane mode)

---

## ✅ Test Scenario 3: No Matches Found

### Steps:
1. Scan an image that is unlikely to match (e.g., random photo, blurry image, non-vinyl object)
2. Wait for processing to complete
3. Observe ResultView

### Expected Results:
- [ ] ResultView shows clean error state (no carousel)
- [ ] Error message displayed: "No matches found" or similar
- [ ] Scanned image still visible
- [ ] Option to retry or go back
- [ ] No crash or blank screen
- [ ] ExtractedData fields are NOT prominently displayed (hidden or in debug mode only)

### Pass Criteria:
✅ Graceful handling with clear user feedback  
✅ No UI layout issues

---

## ✅ Test Scenario 4: Discogs API Error

### Steps:
1. Temporarily remove Discogs token from Settings → Save
2. Attempt a new scan
3. Wait for processing to complete
4. Observe error handling

### Alternative:
- Test with airplane mode enabled during scan (to trigger network error)

### Expected Results:
- [ ] ProcessingView completes (Vision API may succeed)
- [ ] ResultView shows Discogs error banner or error state
- [ ] Error message is user-friendly (not technical stack trace)
- [ ] Option to retry or configure API key
- [ ] App doesn't crash
- [ ] Extracted data from Vision API may still be visible (if debug mode enabled)

### Pass Criteria:
✅ Clear error messaging  
✅ App remains stable  
✅ User can recover (add token, retry)

---

## ✅ Test Scenario 5: Vision API Error

### Steps:
1. Temporarily remove OpenAI API key from Settings → Save
2. Attempt a new scan
3. Observe error handling

### Expected Results:
- [ ] Processing fails early (Vision API required first)
- [ ] Error message: "OpenAI API key not configured" or similar
- [ ] Redirect to SettingsView or show retry option
- [ ] No crash or incomplete data state

### Pass Criteria:
✅ Graceful handling of missing API key  
✅ Clear call-to-action for user

---

## ✅ Test Scenario 6: Multiple Similar Releases (Reissues/Pressings)

### Test Images:
Use famous albums with many pressings (e.g., "Kind of Blue" by Miles Davis, "Abbey Road" by The Beatles)

### Steps:
1. Scan a popular album
2. Wait for carousel to load
3. Observe match cards

### Expected Results:
- [ ] Carousel shows multiple matches (3-5)
- [ ] Each card displays different year/label/catalog number
- [ ] Match scores vary (highest confidence first)
- [ ] Year, label, catalog clearly visible to help differentiate
- [ ] User can compare cards by scrolling
- [ ] Selecting each match shows correct DetailView data

### Pass Criteria:
✅ User can distinguish between similar releases  
✅ Metadata is accurate and helpful  
✅ Match scoring algorithm prioritizes correctly

---

## ✅ Test Scenario 7: Rate Limiting (Rapid Scans)

### Steps:
1. Perform 10-15 rapid scans in quick succession (use gallery images to speed up)
2. Monitor behavior

### Expected Results:
- [ ] First ~5-10 scans process normally
- [ ] Subsequent scans may experience delays (exponential backoff)
- [ ] No crashes or frozen UI
- [ ] ProcessingView may show longer spinner for rate-limited requests
- [ ] Eventually all scans complete successfully
- [ ] No "429 Rate Limit" errors visible to user (handled gracefully)

### Pass Criteria:
✅ App handles rate limiting with backoff  
✅ No data corruption or incomplete saves  
✅ User experience degrades gracefully (slower, but stable)

---

## ✅ Test Scenario 8: Edge Cases & UI States

### 8a. Partial Extraction (Low Confidence)
**Steps:**
1. Scan a blurry or obscured vinyl image
2. Observe match quality

**Expected:**
- [ ] Matches found (even if low confidence)
- [ ] Low confidence scores visible (< 0.5)
- [ ] User can still select a match
- [ ] ExtractedData not prominently displayed (debug only)

---

### 8b. Singles vs Albums
**Steps:**
1. Scan a 7" single or EP
2. Verify track listing extraction

**Expected:**
- [ ] Vision API extracts track titles
- [ ] Discogs search uses track titles in query
- [ ] Matches are accurate for singles (not just albums)

---

### 8c. Back Navigation During Processing
**Steps:**
1. Start a scan
2. During ProcessingView animation, tap back button
3. Observe behavior

**Expected:**
- [ ] Can navigate back (cancel scan)
- [ ] No crash
- [ ] Incomplete scan not saved to history
- [ ] Or: ProcessingView blocks back navigation until complete (acceptable)

---

### 8d. Memory/Performance
**Steps:**
1. Scan 20+ records
2. Scroll through HistoryView
3. Open multiple saved scans
4. Monitor app responsiveness

**Expected:**
- [ ] No memory leaks or crashes
- [ ] Smooth scrolling in HistoryView
- [ ] Images load quickly (cached)
- [ ] App remains responsive

---

## ✅ Test Scenario 9: DetailView Functionality

### Steps:
1. Open any scan with selected match
2. Interact with DetailView elements

### Expected Results:
- [ ] Large album artwork displays (or placeholder if missing)
- [ ] Release title, artist, year prominently displayed
- [ ] Label, catalog number visible
- [ ] Genres displayed as tags/chips
- [ ] Track listing visible (if available in DiscogsMatch)
- [ ] Pricing info displayed (lowest/median if available)
- [ ] "View on Discogs" button functional
- [ ] Tapping button opens Safari with correct release URL
- [ ] URL format: `https://www.discogs.com/release/{releaseId}`
- [ ] No ExtractedData (AI fields) visible in DetailView

### Pass Criteria:
✅ All UI elements render correctly  
✅ Discogs link works  
✅ Layout adapts to missing data gracefully

---

## ✅ Test Scenario 10: Settings & First-Run Experience

### 10a. First Launch (No API Keys)
**Steps:**
1. Delete app → Reinstall
2. Launch app

**Expected:**
- [ ] SettingsView presented as sheet on first launch
- [ ] Prompt to enter OpenAI key and Discogs token
- [ ] Cannot proceed with scan until keys configured

---

### 10b. Settings Validation
**Steps:**
1. Open Settings
2. Test API key management

**Expected:**
- [ ] Can view/edit OpenAI API key
- [ ] Can view/edit Discogs token
- [ ] Keys stored securely (Keychain)
- [ ] Placeholder text visible for empty fields
- [ ] Changes persist after app restart

---

## 📊 Summary Checklist

After completing all tests, verify:

- [x] **Navigation Flow:** HistoryView → ProcessingView → ResultView (carousel) → DetailView
- [x] **Data Persistence:** Scans saved with images, metadata, selected match index
- [x] **Error Handling:** API errors, no matches, missing keys all handled gracefully
- [x] **Performance:** No crashes, smooth animations, responsive UI
- [x] **Offline Mode:** Can browse saved scans without network
- [x] **Code Quality:** No linter errors, SwiftUI warnings, or debug print statements in logs

---

## 🐛 Issues Found

_Document any bugs or regressions discovered during testing:_

1. **Issue:** [Description]
   - **Steps to Reproduce:**
   - **Expected vs Actual:**
   - **Severity:** Critical / High / Medium / Low

2. **Issue:** [Description]
   - **Steps to Reproduce:**
   - **Expected vs Actual:**
   - **Severity:** Critical / High / Medium / Low

---

## ✅ Sign-Off

**Tester:** ___________________  
**Date:** ___________________  
**Result:** PASS / FAIL / PASS WITH ISSUES  

**Notes:**

---

## Appendix: Quick Test Commands

```bash
# Build and run
cd "/Users/vcoulon2/Projects/Flip Side"
./build.sh run

# Clean build
./build.sh clean

# Build without launching
./build.sh simulator
```

## Appendix: Sample Test Data

For consistent testing, use these Discogs-known albums:

1. **High Match Confidence:**
   - Miles Davis - "Kind of Blue"
   - Pink Floyd - "The Dark Side of the Moon"
   - The Beatles - "Abbey Road"

2. **Singles/EPs:**
   - Any 7" single with clear track listing
   - 12" dance singles

3. **Challenging Cases:**
   - Obscure indie releases
   - Foreign language labels
   - Colored vinyl (harder OCR)
   - Picture discs

---

**End of Test Plan**
