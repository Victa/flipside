# Quick Start Testing Guide - Task 23g

**Build & Run:**
```bash
cd "/Users/vcoulon2/Projects/Flip Side"
./build.sh run
```

---

## ✅ Pre-Flight Checklist (Do This First)

1. **Configure API Keys in Settings:**
   - OpenAI API Key (required)
   - Discogs Personal Access Token (required for matches)

2. **Prepare Test Images:**
   - Have 5-10 vinyl record photos ready (mix of covers and labels)
   - Include at least one blurry/unclear image
   - Include at least one famous album (Beatles, Pink Floyd, Miles Davis)

---

## 🔥 Critical Test Scenarios (Do These in Order)

### Test 1: New Scan Happy Path (5 min)
✅ **Goal:** Verify complete flow from scan → carousel → detail

1. Tap FAB → Select image
2. Wait for processing
3. **Check:** Horizontal carousel appears with 3-5 cards
4. **Check:** Cards show artwork, title, confidence scores
5. **Check:** Cards are scrollable horizontally
6. Tap a match card
7. **Check:** DetailView opens with full release info
8. **Check:** "View on Discogs" button opens Safari
9. **Check:** Back button returns to carousel
10. Tap different card
11. **Check:** DetailView updates correctly

**Pass Criteria:** No crashes, smooth navigation, all data displays correctly

---

### Test 2: Reopen Saved Scans (2 min)
✅ **Goal:** Verify navigation logic based on selectedMatchIndex

1. From HistoryView, tap a scan **with no previously selected match**
2. **Expected:** Opens carousel (ResultView)
3. Go back, tap a scan **where you previously selected a match**
4. **Expected:** Opens DetailView directly (skips carousel)

**Pass Criteria:** Direct navigation works, no unnecessary API calls

---

### Test 3: No Matches Scenario (2 min)
✅ **Goal:** Verify graceful error handling

1. Scan a random non-vinyl image (e.g., your desk, a cat photo)
2. Wait for processing
3. **Check:** Clean error state with "No matches found" message
4. **Check:** No crash, no blank screen

**Pass Criteria:** User-friendly error message, app remains stable

---

### Test 4: Missing API Key Error (2 min)
✅ **Goal:** Verify error handling for missing credentials

1. Go to Settings → Delete Discogs token → Save
2. Attempt a new scan
3. **Check:** Error message shown (Discogs search will fail)
4. **Check:** App doesn't crash
5. Re-add token and retry

**Pass Criteria:** Clear error messaging, user can recover

---

### Test 5: Multiple Similar Releases (3 min)
✅ **Goal:** Verify match differentiation

1. Scan a popular album (e.g., "Kind of Blue", "Abbey Road")
2. **Check:** Carousel shows 3-5 different pressings
3. **Check:** Each card shows different year/label/catalog
4. **Check:** Match scores vary (highest confidence first)

**Pass Criteria:** User can distinguish between reissues

---

### Test 6: Rapid Scans (Rate Limiting) (3 min)
✅ **Goal:** Verify rate limit handling

1. Scan 10 images rapidly (use gallery for speed)
2. **Check:** First 5-10 complete normally
3. **Check:** Subsequent scans may be slower (backoff)
4. **Check:** No crashes, all eventually complete

**Pass Criteria:** Graceful degradation, no data corruption

---

### Test 7: Offline Mode (2 min)
✅ **Goal:** Verify offline browsing

1. Complete 2-3 scans with network on
2. Enable Airplane Mode
3. Browse HistoryView
4. Open saved scans
5. **Check:** Can view all saved data (images, metadata)
6. **Check:** Offline banner shown
7. **Check:** Cannot create new scans (FAB disabled or warning shown)

**Pass Criteria:** All cached data accessible offline

---

### Test 8: UI/Performance Check (2 min)
✅ **Goal:** Verify smooth animations and memory stability

1. Scroll through HistoryView with 10+ scans
2. Open multiple DetailViews
3. Navigate back and forth between views
4. **Check:** Smooth animations
5. **Check:** No lag or memory warnings
6. **Check:** Images load quickly

**Pass Criteria:** Responsive UI, no memory leaks

---

## 🐛 Bug Tracking Template

If you find issues, document them here:

```
**Bug #1:**
- Severity: [Critical/High/Medium/Low]
- Steps to Reproduce:
  1.
  2.
  3.
- Expected: 
- Actual:
- Screenshots/Console logs:
```

---

## ✅ Final Sign-Off

After completing all tests above, check these:

- [ ] All navigation flows work (History → Processing → Result → Detail)
- [ ] No crashes encountered
- [ ] Error states are user-friendly
- [ ] API key management works
- [ ] Offline mode functional
- [ ] Performance is acceptable
- [ ] No UI layout issues
- [ ] Discogs links open correctly

**If all checks pass:** Task 23g is complete! ✅

**If any issues found:** Document bugs above, fix critical issues, re-test

---

**Total estimated testing time:** 20-25 minutes

